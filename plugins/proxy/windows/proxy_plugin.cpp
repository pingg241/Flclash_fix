#include "proxy_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <WinInet.h>
#include <Ras.h>
#include <RasError.h>
#include <optional>
#include <string>
#include <vector>

#pragma comment(lib, "wininet")
#pragma comment(lib, "Rasapi32")

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

namespace
{

std::wstring Utf8ToWide(const std::string& value)
{
  if (value.empty())
  {
    return {};
  }
  const int size = MultiByteToWideChar(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0)
  {
    return {};
  }
  std::wstring result(size, L'\0');
  MultiByteToWideChar(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
      result.data(), size);
  return result;
}

std::string WideToUtf8(const std::wstring& value)
{
  if (value.empty())
  {
    return {};
  }
  const int size = WideCharToMultiByte(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0,
      nullptr, nullptr);
  if (size <= 0)
  {
    return {};
  }
  std::string result(size, '\0');
  WideCharToMultiByte(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
      result.data(), size, nullptr, nullptr);
  return result;
}

std::wstring BuildBypassList(const flutter::EncodableList& bypassDomain)
{
  std::wstring bypassList;
  for (const auto& domain : bypassDomain) {
    const auto* value = std::get_if<std::string>(&domain);
    if (value == nullptr)
    {
      continue;
    }
    if (!bypassList.empty()) {
       bypassList += L";";
    }
    bypassList += Utf8ToWide(*value);
  }
  return bypassList;
}

bool SetOptionsForConnection(
    INTERNET_PER_CONN_OPTION_LIST& list,
    LPTSTR connection)
{
  list.pszConnection = connection;
  return InternetSetOption(
      nullptr,
      INTERNET_OPTION_PER_CONNECTION_OPTION,
      &list,
      sizeof(list)) != FALSE;
}

bool ApplyOptionsToConnections(INTERNET_PER_CONN_OPTION_LIST& list)
{
  bool success = SetOptionsForConnection(list, nullptr);

  DWORD size = 0;
  DWORD count = 0;
  auto ret = RasEnumEntries(nullptr, nullptr, nullptr, &size, &count);
  if (ret == ERROR_BUFFER_TOO_SMALL && count > 0)
  {
    std::vector<RASENTRYNAME> entries(count);
    for (auto& entry : entries)
    {
      entry.dwSize = sizeof(RASENTRYNAME);
    }
    ret = RasEnumEntries(nullptr, nullptr, entries.data(), &size, &count);
    if (ret == ERROR_SUCCESS)
    {
      for (DWORD i = 0; i < count; i++)
      {
        success = SetOptionsForConnection(list, entries[i].szEntryName) && success;
      }
    }
    else
    {
      success = false;
    }
  }
  else if (ret != ERROR_SUCCESS)
  {
    success = false;
  }

  return success;
}

bool NotifySettingsChanged()
{
  const bool changed = InternetSetOption(
      nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0) != FALSE;
  const bool refreshed = InternetSetOption(
      nullptr, INTERNET_OPTION_REFRESH, nullptr, 0) != FALSE;
  return changed && refreshed;
}

std::vector<std::wstring> GetConnectionNames(bool* success)
{
  std::vector<std::wstring> names;
  DWORD size = 0;
  DWORD count = 0;
  auto ret = RasEnumEntries(nullptr, nullptr, nullptr, &size, &count);
  if (ret == ERROR_SUCCESS)
  {
    *success = true;
    return names;
  }
  if (ret != ERROR_BUFFER_TOO_SMALL || count == 0)
  {
    *success = false;
    return names;
  }
  std::vector<RASENTRYNAME> entries(count);
  for (auto& entry : entries)
  {
    entry.dwSize = sizeof(RASENTRYNAME);
  }
  ret = RasEnumEntries(nullptr, nullptr, entries.data(), &size, &count);
  if (ret != ERROR_SUCCESS)
  {
    *success = false;
    return names;
  }
  for (DWORD index = 0; index < count; ++index)
  {
    names.emplace_back(entries[index].szEntryName);
  }
  *success = true;
  return names;
}

std::optional<flutter::EncodableMap> CaptureConnection(
    const std::optional<std::wstring>& connection)
{
  std::vector<INTERNET_PER_CONN_OPTION> options(4);
  options[0].dwOption = INTERNET_PER_CONN_FLAGS;
  options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  options[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
  options[3].dwOption = INTERNET_PER_CONN_AUTOCONFIG_URL;

  INTERNET_PER_CONN_OPTION_LIST list = {};
  list.dwSize = sizeof(list);
  list.pszConnection = connection.has_value()
      ? const_cast<wchar_t*>(connection->c_str())
      : nullptr;
  list.dwOptionCount = static_cast<DWORD>(options.size());
  list.pOptions = options.data();
  DWORD size = sizeof(list);
  if (!InternetQueryOption(
          nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list, &size))
  {
    return std::nullopt;
  }

  flutter::EncodableMap result;
  result[flutter::EncodableValue("connection")] = connection.has_value()
      ? flutter::EncodableValue(WideToUtf8(*connection))
      : flutter::EncodableValue();
  result[flutter::EncodableValue("flags")] =
      flutter::EncodableValue(static_cast<int64_t>(options[0].Value.dwValue));
  const char* keys[] = {"proxyServer", "proxyBypass", "autoConfigUrl"};
  for (size_t index = 1; index < options.size(); ++index)
  {
    const auto value = options[index].Value.pszValue;
    result[flutter::EncodableValue(keys[index - 1])] =
        flutter::EncodableValue(
            value == nullptr ? std::string() : WideToUtf8(value));
    if (value != nullptr)
    {
      GlobalFree(value);
    }
  }
  return result;
}

std::optional<flutter::EncodableMap> captureProxy()
{
  flutter::EncodableList connections;
  const auto defaultConnection = CaptureConnection(std::nullopt);
  if (!defaultConnection.has_value())
  {
    return std::nullopt;
  }
  connections.emplace_back(*defaultConnection);
  bool rasSuccess = false;
  for (const auto& name : GetConnectionNames(&rasSuccess))
  {
    const auto connection = CaptureConnection(name);
    if (!connection.has_value())
    {
      return std::nullopt;
    }
    connections.emplace_back(*connection);
  }
  if (!rasSuccess)
  {
    return std::nullopt;
  }
  flutter::EncodableMap snapshot;
  snapshot[flutter::EncodableValue("connections")] =
      flutter::EncodableValue(connections);
  return snapshot;
}

const flutter::EncodableValue* FindValue(
    const flutter::EncodableMap& map,
    const char* key)
{
  const auto iterator = map.find(flutter::EncodableValue(key));
  return iterator == map.end() ? nullptr : &iterator->second;
}

bool RestoreConnection(const flutter::EncodableMap& snapshot)
{
  const auto* connectionValue = FindValue(snapshot, "connection");
  const auto* flagsValue = FindValue(snapshot, "flags");
  const auto* serverValue = FindValue(snapshot, "proxyServer");
  const auto* bypassValue = FindValue(snapshot, "proxyBypass");
  const auto* autoConfigValue = FindValue(snapshot, "autoConfigUrl");
  if (connectionValue == nullptr)
  {
    return false;
  }

  std::optional<int64_t> flags;
  if (flagsValue != nullptr)
  {
    if (const auto* value = std::get_if<int32_t>(flagsValue))
    {
      flags = *value;
    }
    else if (const auto* wideValue = std::get_if<int64_t>(flagsValue))
    {
      flags = *wideValue;
    }
    else
    {
      return false;
    }
  }
  const auto* server = serverValue == nullptr
      ? nullptr
      : std::get_if<std::string>(serverValue);
  const auto* bypass = bypassValue == nullptr
      ? nullptr
      : std::get_if<std::string>(bypassValue);
  const auto* autoConfig = autoConfigValue == nullptr
      ? nullptr
      : std::get_if<std::string>(autoConfigValue);
  if ((serverValue != nullptr && server == nullptr) ||
      (bypassValue != nullptr && bypass == nullptr) ||
      (autoConfigValue != nullptr && autoConfig == nullptr))
  {
    return false;
  }

  std::optional<std::wstring> connection;
  if (!std::holds_alternative<std::monostate>(*connectionValue))
  {
    const auto* name = std::get_if<std::string>(connectionValue);
    if (name == nullptr)
    {
      return false;
    }
    connection = Utf8ToWide(*name);
  }
  auto wideServer = server == nullptr ? std::wstring() : Utf8ToWide(*server);
  auto wideBypass = bypass == nullptr ? std::wstring() : Utf8ToWide(*bypass);
  auto wideAutoConfig = autoConfig == nullptr
      ? std::wstring()
      : Utf8ToWide(*autoConfig);
  std::vector<INTERNET_PER_CONN_OPTION> options;
  if (flags.has_value())
  {
    INTERNET_PER_CONN_OPTION option = {};
    option.dwOption = INTERNET_PER_CONN_FLAGS;
    option.Value.dwValue = static_cast<DWORD>(*flags);
    options.push_back(option);
  }
  if (server != nullptr)
  {
    INTERNET_PER_CONN_OPTION option = {};
    option.dwOption = INTERNET_PER_CONN_PROXY_SERVER;
    option.Value.pszValue = wideServer.data();
    options.push_back(option);
  }
  if (bypass != nullptr)
  {
    INTERNET_PER_CONN_OPTION option = {};
    option.dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
    option.Value.pszValue = wideBypass.data();
    options.push_back(option);
  }
  if (autoConfig != nullptr)
  {
    INTERNET_PER_CONN_OPTION option = {};
    option.dwOption = INTERNET_PER_CONN_AUTOCONFIG_URL;
    option.Value.pszValue = wideAutoConfig.data();
    options.push_back(option);
  }
  if (options.empty())
  {
    return false;
  }

  INTERNET_PER_CONN_OPTION_LIST list = {};
  list.dwSize = sizeof(list);
  list.pszConnection = connection.has_value() ? connection->data() : nullptr;
  list.dwOptionCount = static_cast<DWORD>(options.size());
  list.pOptions = options.data();
  return SetOptionsForConnection(list, list.pszConnection);
}

bool restoreProxy(const flutter::EncodableMap& snapshot)
{
  const auto* value = FindValue(snapshot, "connections");
  const auto* connections = value == nullptr
      ? nullptr
      : std::get_if<flutter::EncodableList>(value);
  if (connections == nullptr || connections->empty())
  {
    return false;
  }
  bool success = true;
  for (const auto& item : *connections)
  {
    const auto* connection = std::get_if<flutter::EncodableMap>(&item);
    success = connection != nullptr && RestoreConnection(*connection) && success;
  }
  const bool notified = NotifySettingsChanged();
  return success && notified;
}

bool startProxy(const int port, const flutter::EncodableList& bypassDomain)
{
  auto url = Utf8ToWide("127.0.0.1:" + std::to_string(port));
  auto bypassList = BuildBypassList(bypassDomain);
  std::vector<INTERNET_PER_CONN_OPTION> options(3);

  INTERNET_PER_CONN_OPTION_LIST list = {};
  list.dwSize = sizeof(list);
  list.dwOptionCount = static_cast<DWORD>(options.size());
  list.pOptions = options.data();

  options[0].dwOption = INTERNET_PER_CONN_FLAGS;
  options[0].Value.dwValue = PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY;

  options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  options[1].Value.pszValue = url.data();

  options[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
  options[2].Value.pszValue = bypassList.data();

  return ApplyOptionsToConnections(list) && NotifySettingsChanged();
}

bool stopProxy()
{
  std::vector<INTERNET_PER_CONN_OPTION> options(1);

  INTERNET_PER_CONN_OPTION_LIST list = {};
  list.dwSize = sizeof(list);
  list.dwOptionCount = 1;
  list.pOptions = options.data();

  options[0].dwOption = INTERNET_PER_CONN_FLAGS;
  options[0].Value.dwValue = PROXY_TYPE_DIRECT;

  return ApplyOptionsToConnections(list) && NotifySettingsChanged();
}

}  // namespace

namespace proxy
{

  // static
  void ProxyPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "proxy",
            &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<ProxyPlugin>();

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

  ProxyPlugin::ProxyPlugin() {}

  ProxyPlugin::~ProxyPlugin() {}

  void ProxyPlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {
    if (method_call.method_name().compare("StopProxy") == 0)
    {
      result->Success(stopProxy());
    }
    else if (method_call.method_name().compare("CaptureProxy") == 0)
    {
      const auto snapshot = captureProxy();
      if (!snapshot.has_value())
      {
        result->Error("capture_failed", "Unable to query system proxy settings");
        return;
      }
      result->Success(*snapshot);
    }
    else if (method_call.method_name().compare("RestoreProxy") == 0)
    {
      const auto* arguments =
          std::get_if<flutter::EncodableMap>(method_call.arguments());
      if (arguments == nullptr)
      {
        result->Error("bad_args", "RestoreProxy requires a snapshot map");
        return;
      }
      result->Success(restoreProxy(*arguments));
    }
    else if (method_call.method_name().compare("StartProxy") == 0)
    {
      auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      if (arguments == nullptr)
      {
        result->Error("bad_args", "StartProxy requires argument map");
        return;
      }
      auto portIt = arguments->find(flutter::EncodableValue("port"));
      auto bypassDomainIt = arguments->find(flutter::EncodableValue("bypassDomain"));
      if (portIt == arguments->end() || bypassDomainIt == arguments->end())
      {
        result->Error("bad_args", "StartProxy requires port and bypassDomain");
        return;
      }
      auto *port = std::get_if<int>(&portIt->second);
      auto *bypassDomain = std::get_if<flutter::EncodableList>(&bypassDomainIt->second);
      if (port == nullptr || bypassDomain == nullptr)
      {
        result->Error("bad_args", "StartProxy argument types are invalid");
        return;
      }
      result->Success(startProxy(*port, *bypassDomain));
    }
    else
    {
      result->NotImplemented();
    }
  }
} // namespace proxy
