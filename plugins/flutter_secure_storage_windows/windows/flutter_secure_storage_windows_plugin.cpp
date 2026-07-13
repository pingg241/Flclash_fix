#include "flutter_secure_storage_windows_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>
#include <wincred.h>
#include <ShlObj_core.h>
#include <sys/stat.h>
#include <errno.h>
#include <direct.h>
#include <bcrypt.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cwctype>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#pragma comment(lib, "version.lib")
#pragma comment(lib, "bcrypt.lib")

namespace flutter_secure_storage_windows
{

  namespace
  {
    constexpr DWORD kEncryptionKeySize = 16;
    constexpr DWORD kNonceSize = 12;

    enum class NativeResource {
      kKnownFolderPath,
      kCredentialBuffer,
      kFindHandle,
      kAlgorithmHandle,
      kKeyHandle,
    };

#if defined(FLUTTER_SECURE_STORAGE_WINDOWS_TESTING)
    struct NativeResourceCounters {
      std::atomic<long> known_folder_paths{0};
      std::atomic<long> credential_buffers{0};
      std::atomic<long> find_handles{0};
      std::atomic<long> algorithm_handles{0};
      std::atomic<long> key_handles{0};
    };

    NativeResourceCounters native_resource_counters;
#endif

    void ResourceAcquired(NativeResource resource) noexcept
    {
#if defined(FLUTTER_SECURE_STORAGE_WINDOWS_TESTING)
      switch (resource) {
        case NativeResource::kKnownFolderPath:
          ++native_resource_counters.known_folder_paths;
          break;
        case NativeResource::kCredentialBuffer:
          ++native_resource_counters.credential_buffers;
          break;
        case NativeResource::kFindHandle:
          ++native_resource_counters.find_handles;
          break;
        case NativeResource::kAlgorithmHandle:
          ++native_resource_counters.algorithm_handles;
          break;
        case NativeResource::kKeyHandle:
          ++native_resource_counters.key_handles;
          break;
      }
#else
      (void)resource;
#endif
    }

    void ResourceReleased(NativeResource resource) noexcept
    {
#if defined(FLUTTER_SECURE_STORAGE_WINDOWS_TESTING)
      switch (resource) {
        case NativeResource::kKnownFolderPath:
          --native_resource_counters.known_folder_paths;
          break;
        case NativeResource::kCredentialBuffer:
          --native_resource_counters.credential_buffers;
          break;
        case NativeResource::kFindHandle:
          --native_resource_counters.find_handles;
          break;
        case NativeResource::kAlgorithmHandle:
          --native_resource_counters.algorithm_handles;
          break;
        case NativeResource::kKeyHandle:
          --native_resource_counters.key_handles;
          break;
      }
#else
      (void)resource;
#endif
    }

    struct KnownFolderPathDeleter {
      void operator()(wchar_t* value) const noexcept
      {
        if (value != nullptr) {
          CoTaskMemFree(value);
          ResourceReleased(NativeResource::kKnownFolderPath);
        }
      }
    };

    struct CredentialBufferDeleter {
      void operator()(void* value) const noexcept
      {
        if (value != nullptr) {
          CredFree(value);
          ResourceReleased(NativeResource::kCredentialBuffer);
        }
      }
    };

    struct FindHandleDeleter {
      void operator()(void* value) const noexcept
      {
        if (value != nullptr) {
          FindClose(value);
          ResourceReleased(NativeResource::kFindHandle);
        }
      }
    };

    struct AlgorithmHandleDeleter {
      void operator()(void* value) const noexcept
      {
        if (value != nullptr) {
          BCryptCloseAlgorithmProvider(value, 0);
          ResourceReleased(NativeResource::kAlgorithmHandle);
        }
      }
    };

    struct KeyHandleDeleter {
      void operator()(void* value) const noexcept
      {
        if (value != nullptr) {
          BCryptDestroyKey(value);
          ResourceReleased(NativeResource::kKeyHandle);
        }
      }
    };

    using UniqueKnownFolderPath =
        std::unique_ptr<wchar_t, KnownFolderPathDeleter>;
    using UniqueCredential =
        std::unique_ptr<CREDENTIALW, CredentialBufferDeleter>;
    using UniqueCredentialList =
        std::unique_ptr<PCREDENTIALW, CredentialBufferDeleter>;
    using UniqueFindHandle = std::unique_ptr<void, FindHandleDeleter>;
    using UniqueAlgorithmHandle =
        std::unique_ptr<void, AlgorithmHandleDeleter>;
    using UniqueKeyHandle = std::unique_ptr<void, KeyHandleDeleter>;

    UniqueKnownFolderPath AdoptKnownFolderPath(LPWSTR value)
    {
      if (value != nullptr) {
        ResourceAcquired(NativeResource::kKnownFolderPath);
      }
      return UniqueKnownFolderPath(value);
    }

    UniqueCredential AdoptCredential(PCREDENTIALW value)
    {
      if (value != nullptr) {
        ResourceAcquired(NativeResource::kCredentialBuffer);
      }
      return UniqueCredential(value);
    }

    UniqueCredentialList AdoptCredentialList(PCREDENTIALW* value)
    {
      if (value != nullptr) {
        ResourceAcquired(NativeResource::kCredentialBuffer);
      }
      return UniqueCredentialList(value);
    }

    UniqueFindHandle AdoptFindHandle(HANDLE value)
    {
      if (value == INVALID_HANDLE_VALUE) {
        return UniqueFindHandle();
      }
      ResourceAcquired(NativeResource::kFindHandle);
      return UniqueFindHandle(value);
    }

    UniqueAlgorithmHandle AdoptAlgorithmHandle(BCRYPT_ALG_HANDLE value)
    {
      if (value != nullptr) {
        ResourceAcquired(NativeResource::kAlgorithmHandle);
      }
      return UniqueAlgorithmHandle(value);
    }

    UniqueKeyHandle AdoptKeyHandle(BCRYPT_KEY_HANDLE value)
    {
      if (value != nullptr) {
        ResourceAcquired(NativeResource::kKeyHandle);
      }
      return UniqueKeyHandle(value);
    }

    std::wstring AnsiToWide(const std::string& value)
    {
      if (value.empty()) {
        return {};
      }
      if (value.size() >
          static_cast<size_t>((std::numeric_limits<int>::max)())) {
        throw ERROR_INVALID_PARAMETER;
      }

      const int value_size = static_cast<int>(value.size());
      const int wide_size = MultiByteToWideChar(
          CP_ACP, 0, value.data(), value_size, nullptr, 0);
      if (wide_size == 0) {
        throw GetLastError();
      }

      std::wstring result(wide_size, L'\0');
      if (MultiByteToWideChar(
              CP_ACP, 0, value.data(), value_size, result.data(), wide_size) ==
          0) {
        throw GetLastError();
      }
      return result;
    }

    std::string WideToAnsi(const wchar_t* value)
    {
      if (value == nullptr || *value == L'\0') {
        return {};
      }

      const int ansi_size =
          WideCharToMultiByte(CP_ACP, 0, value, -1, nullptr, 0, nullptr, nullptr);
      if (ansi_size == 0) {
        throw GetLastError();
      }

      std::string result(static_cast<size_t>(ansi_size), '\0');
      if (WideCharToMultiByte(CP_ACP, 0, value, -1, result.data(), ansi_size,
                              nullptr, nullptr) == 0) {
        throw GetLastError();
      }
      result.resize(static_cast<size_t>(ansi_size - 1));
      return result;
    }

    std::string CredentialValue(const CREDENTIALW& credential)
    {
      if (credential.CredentialBlobSize == 0) {
        return {};
      }
      if (credential.CredentialBlob == nullptr) {
        throw ERROR_INVALID_DATA;
      }
      const auto* begin =
          reinterpret_cast<const char*>(credential.CredentialBlob);
      std::string value(begin, begin + credential.CredentialBlobSize);
      if (!value.empty() && value.back() == '\0') {
        value.pop_back();
      }
      return value;
    }
  }  // namespace

#if defined(FLUTTER_SECURE_STORAGE_WINDOWS_TESTING)
  NativeResourceCounts GetNativeResourceCountsForTesting()
  {
    return {
        native_resource_counters.known_folder_paths.load(),
        native_resource_counters.credential_buffers.load(),
        native_resource_counters.find_handles.load(),
        native_resource_counters.algorithm_handles.load(),
        native_resource_counters.key_handles.load(),
    };
  }
#endif

#if defined(FLUTTER_SECURE_STORAGE_WINDOWS_TESTING)
#if !defined(FLUTTER_SECURE_STORAGE_WINDOWS_TEST_PREFIX)
#error "Native secure-storage tests require an isolated random prefix"
#endif
  const std::string ELEMENT_PREFERENCES_KEY_PREFIX =
      FLUTTER_SECURE_STORAGE_WINDOWS_TEST_PREFIX;
  const std::string PRODUCTION_STORAGE_KEY_PREFIX =
      SECURE_STORAGE_KEY_PREFIX;
#else
  const std::string ELEMENT_PREFERENCES_KEY_PREFIX = SECURE_STORAGE_KEY_PREFIX;
#endif
  const size_t ELEMENT_PREFERENCES_KEY_PREFIX_LENGTH =
      ELEMENT_PREFERENCES_KEY_PREFIX.size();

  // this string is used to filter the credential storage so that only the values written
  // by this plugin shows up.
  const std::wstring CREDENTIAL_FILTER =
      AnsiToWide(ELEMENT_PREFERENCES_KEY_PREFIX + '*');

#if defined(FLUTTER_SECURE_STORAGE_WINDOWS_TESTING)
  const std::string& GetStoragePrefixForTesting()
  {
    return ELEMENT_PREFERENCES_KEY_PREFIX;
  }

  const std::string& GetProductionStoragePrefixForTesting()
  {
    return PRODUCTION_STORAGE_KEY_PREFIX;
  }
#endif

  static inline void rtrim(std::wstring& s) {
      s.erase(std::find_if(s.rbegin(), s.rend(), [](wchar_t ch) {
          return !std::iswspace(ch);
          }).base(), s.end());
  }

  // static
  void FlutterSecureStorageWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "plugins.it_nomads.com/flutter_secure_storage",
            &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<FlutterSecureStorageWindowsPlugin>();

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

  FlutterSecureStorageWindowsPlugin::FlutterSecureStorageWindowsPlugin() {}

  FlutterSecureStorageWindowsPlugin::~FlutterSecureStorageWindowsPlugin() {}

  std::optional<std::string> FlutterSecureStorageWindowsPlugin::GetValueKey(const flutter::EncodableMap *args)
  {
    auto key = this->GetStringArg("key", args);
    if (key.has_value())
      return ELEMENT_PREFERENCES_KEY_PREFIX + key.value();
    return std::nullopt;
  }

  std::string FlutterSecureStorageWindowsPlugin::RemoveKeyPrefix(const std::string& key)
  {
    return key.substr(ELEMENT_PREFERENCES_KEY_PREFIX_LENGTH);
  }

  std::optional<std::string> FlutterSecureStorageWindowsPlugin::GetStringArg(
      const std::string &param,
      const flutter::EncodableMap *args)
  {
    if (args == nullptr)
      return std::nullopt;
    auto p = args->find(param);
    if (p == args->end())
      return std::nullopt;
    return std::get<std::string>(p->second);
  }

  std::string FlutterSecureStorageWindowsPlugin::GetErrorString(const DWORD &error_code)
  {
    switch (error_code)
    {
    case ERROR_NO_SUCH_LOGON_SESSION:
      return "ERROR_NO_SUCH_LOGIN_SESSION";
    case ERROR_INVALID_FLAGS:
      return "ERROR_INVALID_FLAGS";
    case ERROR_BAD_USERNAME:
      return "ERROR_BAD_USERNAME";
    case SCARD_E_NO_READERS_AVAILABLE:
      return "SCARD_E_NO_READERS_AVAILABLE";
    case SCARD_E_NO_SMARTCARD:
      return "SCARD_E_NO_SMARTCARD";
    case SCARD_W_REMOVED_CARD:
      return "SCARD_W_REMOVED_CARD";
    case SCARD_W_WRONG_CHV:
      return "SCARD_W_WRONG_CHV";
    case ERROR_INVALID_PARAMETER:
      return "ERROR_INVALID_PARAMETER";
    default:
      return "UNKNOWN_ERROR";
    }
  }

  std::string FlutterSecureStorageWindowsPlugin::NtStatusToString(const CHAR* operation, NTSTATUS status)
  {
      std::ostringstream oss;
      oss << operation << ", 0x" << std::hex << status;

      switch (status)
      {
      case 0xc0000000:
          oss << " (STATUS_SUCCESS)";
          break;
      case 0xC0000008:
          oss << " (STATUS_INVALID_HANDLE)";
          break;
      case 0xc000000d:
          oss << " (STATUS_INVALID_PARAMETER)";
          break;
      case 0xc00000bb:
          oss << " (STATUS_NOT_SUPPORTED)";
          break;
      case 0xC0000225:
          oss << " (STATUS_NOT_FOUND)";
          break;
      }
      return oss.str();
  }

  DWORD FlutterSecureStorageWindowsPlugin::GetApplicationSupportPath(std::wstring &path)
  {
      LPWSTR raw_appdata_path = nullptr;
      const HRESULT folder_result = SHGetKnownFolderPath(
          FOLDERID_RoamingAppData, KF_FLAG_DEFAULT, nullptr,
          &raw_appdata_path);
      if (FAILED(folder_result)) {
          return HRESULT_CODE(folder_result);
      }
      auto appdata_path = AdoptKnownFolderPath(raw_appdata_path);

      std::wstring company_name = L"placeholder_company";
      std::wstring product_name = L"placeholder_product";
      wchar_t name_buffer[MAX_PATH + 1]{};
      const DWORD module_name_length = GetModuleFileNameW(
          nullptr, name_buffer, static_cast<DWORD>(std::size(name_buffer)));
      if (module_name_length == 0) {
          return GetLastError();
      }
      if (module_name_length == static_cast<DWORD>(std::size(name_buffer)) &&
          GetLastError() == ERROR_INSUFFICIENT_BUFFER) {
          return ERROR_INSUFFICIENT_BUFFER;
      }

      const DWORD version_info_size =
          GetFileVersionInfoSizeW(name_buffer, nullptr);
      if (version_info_size != 0) {
          std::vector<BYTE> info_buffer(version_info_size);
          if (GetFileVersionInfoW(name_buffer, 0, version_info_size,
                                  info_buffer.data()) != 0) {
              UINT query_length = 0;
              LPVOID query_value = nullptr;
              if (VerQueryValueW(
                      info_buffer.data(),
                      L"\\StringFileInfo\\040904e4\\CompanyName",
                      &query_value, &query_length) != 0 ||
                  VerQueryValueW(
                      info_buffer.data(),
                      L"\\StringFileInfo\\040904b0\\CompanyName",
                      &query_value, &query_length) != 0) {
                  company_name = SanitizeDirString(
                      std::wstring(static_cast<const wchar_t*>(query_value)));
              }
              if (VerQueryValueW(
                      info_buffer.data(),
                      L"\\StringFileInfo\\040904e4\\ProductName",
                      &query_value, &query_length) != 0 ||
                  VerQueryValueW(
                      info_buffer.data(),
                      L"\\StringFileInfo\\040904b0\\ProductName",
                      &query_value, &query_length) != 0) {
                  product_name = SanitizeDirString(
                      std::wstring(static_cast<const wchar_t*>(query_value)));
              }
          }
      }

      path = std::wstring(appdata_path.get()) + L"\\" + company_name + L"\\" +
             product_name;
      return ERROR_SUCCESS;
  }

  std::wstring FlutterSecureStorageWindowsPlugin::SanitizeDirString(std::wstring string)
  {
      std::wstring illegalChars = L"\\/:?\"<>|";
      for (auto it = string.begin(); it < string.end(); ++it) {
          if (illegalChars.find(*it) != std::wstring::npos) {
              *it = L'_';
          }
      }
      rtrim(string);
      return string;
  }

  bool FlutterSecureStorageWindowsPlugin::PathExists(const std::wstring& path)
  {
      struct _stat info;
      if (_wstat(path.c_str(), &info) != 0) {
          return false;
      }
      return (info.st_mode & _S_IFDIR) != 0;
  }

  bool FlutterSecureStorageWindowsPlugin::MakePath(const std::wstring& path)
  {
      int ret = _wmkdir(path.c_str());
      if (ret == 0) {
          return true;
      }
      switch (errno) {
      case ENOENT:
        {
          size_t pos = path.find_last_of('/');
          if (pos == std::wstring::npos)
              pos = path.find_last_of('\\');
          if (pos == std::wstring::npos)
              return false;
        if (!MakePath(path.substr(0, pos)))
              return false;
        }
        return 0 == _wmkdir(path.c_str());
      case EEXIST:
          return PathExists(path);
      default:
          return false;
      }
  }

  std::optional<std::array<BYTE, 16>>
  FlutterSecureStorageWindowsPlugin::GetEncryptionKey()
  {
      std::array<BYTE, kEncryptionKeySize> aes_key{};
      const auto target_name =
          AnsiToWide("key_" + ELEMENT_PREFERENCES_KEY_PREFIX);

      PCREDENTIALW raw_credential = nullptr;
      if (CredReadW(target_name.c_str(), CRED_TYPE_GENERIC, 0,
                    &raw_credential)) {
          auto credential = AdoptCredential(raw_credential);
          if (credential->CredentialBlobSize != kEncryptionKeySize) {
              CredDeleteW(target_name.c_str(), CRED_TYPE_GENERIC, 0);
          } else {
              memcpy(aes_key.data(), credential->CredentialBlob,
                     kEncryptionKeySize);
              return aes_key;
          }
      } else if (GetLastError() != ERROR_NOT_FOUND) {
          return std::nullopt;
      }

      const NTSTATUS random_status = BCryptGenRandom(
          nullptr, aes_key.data(), kEncryptionKeySize,
          BCRYPT_USE_SYSTEM_PREFERRED_RNG);
      if (!BCRYPT_SUCCESS(random_status)) {
          return std::nullopt;
      }
      CREDENTIALW cred = { 0 };
      cred.Type = CRED_TYPE_GENERIC;
      cred.TargetName = const_cast<wchar_t*>(target_name.c_str());
      cred.CredentialBlobSize = kEncryptionKeySize;
      cred.CredentialBlob = aes_key.data();
      cred.Persist = CRED_PERSIST_LOCAL_MACHINE;

      if (!CredWriteW(&cred, 0)) {
          std::cerr << "Failed to write encryption key" << std::endl;
          return std::nullopt;
      }
      return aes_key;
  }

  void FlutterSecureStorageWindowsPlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {
    auto method = method_call.method_name();
    const auto *args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    std::wstring path;
    if (GetApplicationSupportPath(path) != ERROR_SUCCESS) {
        result->Error("Exception occurred", "GetApplicationSupportPath");
        return;
    }
    try
    {
      if (method == "write")
      {
        auto key = this->GetValueKey(args);
        auto val = this->GetStringArg("value", args);
        if (key.has_value())
        {
          if (val.has_value())
            this->Write(key.value(), val.value());
          else
            this->Delete(key.value());
          result->Success();
        }
        else
        {
          result->Error("Exception occurred", "write");
        }
      }
      else if (method == "read")
      {
        auto key = this->GetValueKey(args);
        if (key.has_value())
        {
          auto val = this->Read(key.value());
          if (val.has_value())
            result->Success(flutter::EncodableValue(val.value()));
          else
            result->Success();
        }
        else
        {
          result->Error("Exception occurred", "read");
        }
      }
      else if (method == "readAll")
      {
        auto creds = this->ReadAll();
        result->Success(flutter::EncodableValue(creds));
      }
      else if (method == "delete")
      {
        auto key = this->GetValueKey(args);
        if (key.has_value())
        {
          this->Delete(key.value());
          result->Success();
        }
        else
        {
          result->Error("Exception occurred", "delete");
        }
      }
      else if (method == "deleteAll")
      {
        this->DeleteAll();
        result->Success();
      }
      else if (method == "containsKey")
      {
        auto key = this->GetValueKey(args);
        if (key.has_value())
        {
          auto contains_key = this->ContainsKey(key.value());
          result->Success(flutter::EncodableValue(contains_key));
        }
        else
        {
          result->Error("Exception occurred", "containsKey");
        }
      }
      else
      {
        result->NotImplemented();
      }
    }
    catch (DWORD e)
    {
      auto str_code = this->GetErrorString(e);
      result->Error("Exception encountered: " + str_code, method);
    }
    catch (const std::exception& e)
    {
      result->Error("Exception encountered", method + ": " + e.what());
    }
  }

  void FlutterSecureStorageWindowsPlugin::Write(const std::string &key, const std::string &val)
  {
      if (val.size() >= (std::numeric_limits<ULONG>::max)()) {
          throw ERROR_INVALID_PARAMETER;
      }
      auto encryption_key = GetEncryptionKey();
      if (!encryption_key.has_value()) {
          throw std::runtime_error("Failed to obtain encryption key");
      }

      BCRYPT_ALG_HANDLE raw_algorithm = nullptr;
      NTSTATUS status = BCryptOpenAlgorithmProvider(
          &raw_algorithm, BCRYPT_AES_ALGORITHM, nullptr, 0);
      if (!BCRYPT_SUCCESS(status)) {
          throw std::runtime_error(
              NtStatusToString("BCryptOpenAlgorithmProvider", status));
      }
      auto algorithm = AdoptAlgorithmHandle(raw_algorithm);

      status = BCryptSetProperty(
          algorithm.get(), BCRYPT_CHAINING_MODE,
          reinterpret_cast<PUCHAR>(BCRYPT_CHAIN_MODE_GCM),
          sizeof(BCRYPT_CHAIN_MODE_GCM), 0);
      if (!BCRYPT_SUCCESS(status)) {
          throw std::runtime_error(NtStatusToString("BCryptSetProperty", status));
      }

      DWORD bytes_written = 0;
      BCRYPT_AUTH_TAG_LENGTHS_STRUCT auth_tag_lengths{};
      status = BCryptGetProperty(
          algorithm.get(), BCRYPT_AUTH_TAG_LENGTH,
          reinterpret_cast<PBYTE>(&auth_tag_lengths),
          sizeof(auth_tag_lengths), &bytes_written, 0);
      if (!BCRYPT_SUCCESS(status)) {
          throw std::runtime_error(NtStatusToString("BCryptGetProperty", status));
      }

      std::array<BYTE, kNonceSize> iv{};
      status = BCryptGenRandom(nullptr, iv.data(), kNonceSize,
                               BCRYPT_USE_SYSTEM_PREFERRED_RNG);
      if (!BCRYPT_SUCCESS(status)) {
          throw std::runtime_error(NtStatusToString("BCryptGenRandom", status));
      }

      std::array<BYTE, kNonceSize> nonce = iv;
      std::vector<BYTE> auth_tag(auth_tag_lengths.dwMaxLength);
      BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO authInfo{};
      BCRYPT_INIT_AUTH_MODE_INFO(authInfo);
      authInfo.pbNonce = nonce.data();
      authInfo.cbNonce = kNonceSize;
      authInfo.pbAuthData = nullptr;
      authInfo.cbAuthData = 0;
      authInfo.pbTag = auth_tag.data();
      authInfo.cbTag = auth_tag_lengths.dwMaxLength;

      BCRYPT_KEY_HANDLE raw_key = nullptr;
      status = BCryptGenerateSymmetricKey(
          algorithm.get(), &raw_key, nullptr, 0,
          const_cast<PUCHAR>(encryption_key->data()), kEncryptionKeySize, 0);
      if (!BCRYPT_SUCCESS(status)) {
          throw std::runtime_error(
              NtStatusToString("BCryptGenerateSymmetricKey", status));
      }
      auto key_handle = AdoptKeyHandle(raw_key);

      auto* plaintext = reinterpret_cast<PUCHAR>(
          const_cast<char*>(val.c_str()));
      const ULONG plaintext_size = static_cast<ULONG>(val.size() + 1);
      status = BCryptEncrypt(
          key_handle.get(), plaintext, plaintext_size, &authInfo, nullptr, 0,
          nullptr, 0, &bytes_written, 0);
      if (!BCRYPT_SUCCESS(status)) {
          throw std::runtime_error(NtStatusToString("BCryptEncrypt1", status));
      }

      std::vector<BYTE> ciphertext(bytes_written);
      status = BCryptEncrypt(
          key_handle.get(), plaintext, plaintext_size, &authInfo, nullptr, 0,
          ciphertext.data(), static_cast<ULONG>(ciphertext.size()),
          &bytes_written, 0);
      if (!BCRYPT_SUCCESS(status)) {
          throw std::runtime_error(NtStatusToString("BCryptEncrypt2", status));
      }

      std::wstring app_support_path;
      const DWORD path_error = GetApplicationSupportPath(app_support_path);
      if (path_error != ERROR_SUCCESS) {
          throw path_error;
      }
      if (!PathExists(app_support_path) && !MakePath(app_support_path)) {
          throw std::runtime_error("Failed to create application support path");
      }

      std::basic_ofstream<BYTE> fs(
          app_support_path + L"\\" + std::wstring(key.begin(), key.end()) +
              L".secure",
          std::ios::binary | std::ios::trunc);
      if (!fs) {
          throw std::runtime_error("Failed to open output stream");
      }
      fs.write(iv.data(), iv.size());
      fs.write(auth_tag.data(), auth_tag.size());
      fs.write(ciphertext.data(), bytes_written);
      fs.close();
      if (!fs) {
          throw std::runtime_error("Failed to persist encrypted value");
      }
  }

  std::optional<std::string> FlutterSecureStorageWindowsPlugin::Read(const std::string &key)
  {
      std::wstring app_support_path;
      const DWORD path_error = GetApplicationSupportPath(app_support_path);
      if (path_error != ERROR_SUCCESS) {
          throw path_error;
      }

      std::basic_ifstream<BYTE> fs(
          app_support_path + L"\\" + std::wstring(key.begin(), key.end()) +
              L".secure",
          std::ios::binary);
      if (!fs.good()) {
          PCREDENTIALW raw_credential = nullptr;
          const auto target_name = AnsiToWide(key);
          if (CredReadW(target_name.c_str(), CRED_TYPE_GENERIC, 0,
                        &raw_credential)) {
              auto credential = AdoptCredential(raw_credential);
              return CredentialValue(*credential);
          }
          const DWORD credential_error = GetLastError();
          if (credential_error != ERROR_NOT_FOUND) {
              throw credential_error;
          }
          return std::nullopt;
      }

      fs.unsetf(std::ios::skipws);
      fs.seekg(0, std::ios::end);
      const std::streampos file_size_position = fs.tellg();
      if (file_size_position <= 0 ||
          file_size_position >
              static_cast<std::streamoff>((std::numeric_limits<DWORD>::max)())) {
          std::cerr << "Invalid encrypted file size" << std::endl;
          return std::nullopt;
      }
      const size_t file_size = static_cast<size_t>(file_size_position);
      fs.seekg(0, std::ios::beg);
      std::vector<BYTE> file_buffer(file_size);
      if (!fs.read(file_buffer.data(),
                   static_cast<std::streamsize>(file_buffer.size()))) {
          std::cerr << "Failed to read encrypted file" << std::endl;
          return std::nullopt;
      }
      fs.close();

      auto encryption_key = GetEncryptionKey();
      if (!encryption_key.has_value()) {
          std::cerr << "Failed to obtain encryption key" << std::endl;
          return std::nullopt;
      }

      BCRYPT_ALG_HANDLE raw_algorithm = nullptr;
      NTSTATUS status = BCryptOpenAlgorithmProvider(
          &raw_algorithm, BCRYPT_AES_ALGORITHM, nullptr, 0);
      if (!BCRYPT_SUCCESS(status)) {
          std::cerr << NtStatusToString("BCryptOpenAlgorithmProvider", status) << std::endl;
          return std::nullopt;
      }
      auto algorithm = AdoptAlgorithmHandle(raw_algorithm);

      status = BCryptSetProperty(
          algorithm.get(), BCRYPT_CHAINING_MODE,
          reinterpret_cast<PUCHAR>(BCRYPT_CHAIN_MODE_GCM),
          sizeof(BCRYPT_CHAIN_MODE_GCM), 0);
      if (!BCRYPT_SUCCESS(status)) {
          std::cerr << NtStatusToString("BCryptSetProperty", status) << std::endl;
          return std::nullopt;
      }

      DWORD bytes_written = 0;
      BCRYPT_AUTH_TAG_LENGTHS_STRUCT auth_tag_lengths{};
      status = BCryptGetProperty(
          algorithm.get(), BCRYPT_AUTH_TAG_LENGTH,
          reinterpret_cast<PBYTE>(&auth_tag_lengths),
          sizeof(auth_tag_lengths), &bytes_written, 0);
      if (!BCRYPT_SUCCESS(status)) {
          std::cerr << NtStatusToString("BCryptGetProperty", status) << std::endl;
          return std::nullopt;
      }

      const size_t metadata_size =
          static_cast<size_t>(kNonceSize) + auth_tag_lengths.dwMaxLength;
      if (file_size <= metadata_size) {
          std::cerr << "File is too small" << std::endl;
          return std::nullopt;
      }

      std::array<BYTE, kNonceSize> nonce{};
      std::copy_n(file_buffer.begin(), nonce.size(), nonce.begin());
      std::vector<BYTE> auth_tag(auth_tag_lengths.dwMaxLength);
      std::copy_n(file_buffer.begin() + kNonceSize, auth_tag.size(),
                  auth_tag.begin());
      std::vector<BYTE> ciphertext(
          file_buffer.begin() + metadata_size, file_buffer.end());

      BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO auth_info{};
      BCRYPT_INIT_AUTH_MODE_INFO(auth_info);
      auth_info.pbNonce = nonce.data();
      auth_info.cbNonce = kNonceSize;
      auth_info.pbTag = auth_tag.data();
      auth_info.cbTag = auth_tag_lengths.dwMaxLength;

      BCRYPT_KEY_HANDLE raw_key = nullptr;
      status = BCryptGenerateSymmetricKey(
          algorithm.get(), &raw_key, nullptr, 0,
          const_cast<PUCHAR>(encryption_key->data()), kEncryptionKeySize, 0);
      if (!BCRYPT_SUCCESS(status)) {
          std::cerr << NtStatusToString("BCryptGenerateSymmetricKey", status) << std::endl;
          return std::nullopt;
      }
      auto key_handle = AdoptKeyHandle(raw_key);

      status = BCryptDecrypt(
          key_handle.get(), ciphertext.data(),
          static_cast<ULONG>(ciphertext.size()), &auth_info, nullptr, 0,
          nullptr, 0, &bytes_written, 0);
      if (!BCRYPT_SUCCESS(status)) {
          std::cerr << NtStatusToString("BCryptDecrypt1", status) << std::endl;
          return std::nullopt;
      }

      std::vector<BYTE> plaintext(bytes_written);
      status = BCryptDecrypt(
          key_handle.get(), ciphertext.data(),
          static_cast<ULONG>(ciphertext.size()), &auth_info, nullptr, 0,
          plaintext.data(), static_cast<ULONG>(plaintext.size()),
          &bytes_written, 0);
      if (!BCRYPT_SUCCESS(status)) {
          std::cerr << NtStatusToString("BCryptDecrypt2", status) << std::endl;
          return std::nullopt;
      }

      size_t plaintext_length = bytes_written;
      if (plaintext_length != 0 && plaintext[plaintext_length - 1] == '\0') {
          --plaintext_length;
      }
      return std::string(reinterpret_cast<const char*>(plaintext.data()),
                         plaintext_length);
  }

  flutter::EncodableMap FlutterSecureStorageWindowsPlugin::ReadAll()
  {
      WIN32_FIND_DATAW search_result{};
      std::wstring app_support_path;
      flutter::EncodableMap credentials;

      const DWORD path_error = GetApplicationSupportPath(app_support_path);
      if (path_error != ERROR_SUCCESS) {
          throw path_error;
      }
      if (!PathExists(app_support_path)) {
          MakePath(app_support_path);
      }

      HANDLE raw_find_handle = FindFirstFileW(
          (app_support_path + L"\\" +
           AnsiToWide(ELEMENT_PREFERENCES_KEY_PREFIX) + L"*.secure").c_str(),
          &search_result);
      auto find_handle = AdoptFindHandle(raw_find_handle);
      if (find_handle) {
          do {
              std::wstring file_name(search_result.cFileName);
              const size_t suffix_position = file_name.rfind(L".secure");
              if (suffix_position == std::wstring::npos) {
                  continue;
              }
              file_name.erase(suffix_position);
              const std::string stored_key = WideToAnsi(file_name.c_str());
              const auto value = Read(stored_key);
              if (value.has_value()) {
                  credentials[RemoveKeyPrefix(stored_key)] = value.value();
              }
          } while (FindNextFileW(find_handle.get(), &search_result) != 0);
      }

    PCREDENTIALW* raw_credentials = nullptr;
    DWORD cred_count = 0;

    if (!CredEnumerateW(CREDENTIAL_FILTER.c_str(), 0, &cred_count,
                        &raw_credentials)) {
        return credentials;
    }
    auto credential_list = AdoptCredentialList(raw_credentials);
    for (DWORD i = 0; i < cred_count; i++)
    {
      auto pcred = credential_list.get()[i];
      const auto target_name = WideToAnsi(pcred->TargetName);
      auto key = this->RemoveKeyPrefix(target_name);
      //If the key exists then data was already read from a file, which implies that the data read from the credential system is outdated
      if (credentials.find(key) == credentials.end()) {
          credentials[key] = CredentialValue(*pcred);
      }
    }

    return credentials;
  }

  void FlutterSecureStorageWindowsPlugin::Delete(const std::string &key)
  {
      std::wstring appSupportPath;
      GetApplicationSupportPath(appSupportPath);
      auto wstr = std::wstring(key.begin(), key.end());
      BOOL ok = DeleteFile((appSupportPath + L"\\" + wstr + L".secure").c_str());
      if (!ok) {
          DWORD error = GetLastError();
          if (error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND) {
              throw error;
          }
      }

    //Backwards comp.
    ok = CredDeleteW(wstr.c_str(), CRED_TYPE_GENERIC, 0);
    if (!ok)
    {
      auto error = GetLastError();

      // Silently ignore if we try to delete a key that doesn't exist
      if (error == ERROR_NOT_FOUND)
        return;

      throw error;
    }
  }

  void FlutterSecureStorageWindowsPlugin::DeleteAll()
  {

      WIN32_FIND_DATAW search_result{};
      std::wstring app_support_path;

      const DWORD path_error = GetApplicationSupportPath(app_support_path);
      if (path_error != ERROR_SUCCESS) {
          throw path_error;
      }
      if (!PathExists(app_support_path)) {
          MakePath(app_support_path);
      }

      HANDLE raw_find_handle = FindFirstFileW(
          (app_support_path + L"\\" +
           AnsiToWide(ELEMENT_PREFERENCES_KEY_PREFIX) + L"*.secure").c_str(),
          &search_result);
      auto find_handle = AdoptFindHandle(raw_find_handle);
      if (find_handle) {
          do {
              const BOOL ok = DeleteFileW(
                  (app_support_path + L"\\" + search_result.cFileName).c_str());
              if (!ok) {
                  const DWORD error = GetLastError();
                  if (error != ERROR_FILE_NOT_FOUND) {
                      throw error;
                  }
              }
          } while (FindNextFileW(find_handle.get(), &search_result) != 0);
      }

    //Backwards comp.
    PCREDENTIALW* raw_credentials = nullptr;
    DWORD cred_count = 0;

    bool read_ok = CredEnumerateW(CREDENTIAL_FILTER.c_str(), 0, &cred_count, &raw_credentials);
    if (!read_ok)
    {
      auto error = GetLastError();
      if (error == ERROR_NOT_FOUND)
        // No credentials to delete
        return;
      throw error;
    }
    auto credential_list = AdoptCredentialList(raw_credentials);

    for (DWORD i = 0; i < cred_count; i++)
    {
      auto pcred = credential_list.get()[i];
      auto target_name = pcred->TargetName;

      bool delete_ok = CredDeleteW(target_name, CRED_TYPE_GENERIC, 0);
      if (!delete_ok)
      {
        throw GetLastError();
      }
    }
  }

  bool FlutterSecureStorageWindowsPlugin::ContainsKey(const std::string &key)
  {
      std::wstring appSupportPath;
      GetApplicationSupportPath(appSupportPath);
      std::wstring wstr = std::wstring(key.begin(), key.end());
      if (INVALID_FILE_ATTRIBUTES == GetFileAttributes((appSupportPath + L"\\" + wstr + L".secure").c_str())) {
          //Backwards comp.
          PCREDENTIALW raw_credential = nullptr;
          const auto target_name = AnsiToWide(key);

          bool ok = CredReadW(target_name.c_str(), CRED_TYPE_GENERIC, 0, &raw_credential);
          if (ok) {
              auto credential = AdoptCredential(raw_credential);
              return credential != nullptr;
          }

          auto error = GetLastError();
          if (error == ERROR_NOT_FOUND)
              return false;
          throw error;
      }
      return true;
  }
}  // namespace flutter_secure_storage_windows

extern "C" __declspec(dllexport) void FlutterSecureStorageWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar)
{
  flutter_secure_storage_windows::FlutterSecureStorageWindowsPlugin::
      RegisterWithRegistrar(
          flutter::PluginRegistrarManager::GetInstance()
              ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
