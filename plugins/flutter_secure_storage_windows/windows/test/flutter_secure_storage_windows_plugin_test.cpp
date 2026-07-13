#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>
#include <wincred.h>

#include <fstream>
#include <memory>
#include <string>
#include <variant>

#include "flutter_secure_storage_windows_plugin.h"

namespace flutter_secure_storage_windows {
namespace test {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Invoke HandleMethodCall and return true on success, false on error / not-
// implemented.  Optionally captures the success value via |out|.
static bool Invoke(
    FlutterSecureStorageWindowsPlugin& plugin,
    const std::string& method,
    EncodableMap args,
    EncodableValue* out = nullptr) {
  bool succeeded = false;
  plugin.HandleMethodCall(
      MethodCall(method, std::make_unique<EncodableValue>(std::move(args))),
      std::make_unique<MethodResultFunctions<>>(
          [&succeeded, out](const EncodableValue* result) {
            succeeded = true;
            if (out && result) *out = *result;
          },
          /*on_error=*/nullptr,
          /*on_not_implemented=*/nullptr));
  return succeeded;
}

static bool Write(FlutterSecureStorageWindowsPlugin& plugin,
                  const std::string& key, const std::string& value) {
  return Invoke(plugin, "write",
                {{EncodableValue("key"), EncodableValue(key)},
                 {EncodableValue("value"), EncodableValue(value)}});
}

static std::optional<std::string> Read(FlutterSecureStorageWindowsPlugin& plugin,
                                       const std::string& key) {
  EncodableValue out;
  if (!Invoke(plugin, "read", {{EncodableValue("key"), EncodableValue(key)}},
              &out))
    return std::nullopt;
  if (std::holds_alternative<std::string>(out))
    return std::get<std::string>(out);
  return std::nullopt;  // null result == key not present
}

static bool ContainsKey(FlutterSecureStorageWindowsPlugin& plugin,
                        const std::string& key) {
  EncodableValue out;
  Invoke(plugin, "containsKey",
         {{EncodableValue("key"), EncodableValue(key)}}, &out);
  return std::holds_alternative<bool>(out) && std::get<bool>(out);
}

static bool Delete(FlutterSecureStorageWindowsPlugin& plugin,
                   const std::string& key) {
  return Invoke(plugin, "delete",
                {{EncodableValue("key"), EncodableValue(key)}});
}

static bool DeleteAll(FlutterSecureStorageWindowsPlugin& plugin) {
  return Invoke(plugin, "deleteAll", {});
}

static EncodableMap ReadAll(FlutterSecureStorageWindowsPlugin& plugin) {
  EncodableValue out;
  if (!Invoke(plugin, "readAll", {}, &out) ||
      !std::holds_alternative<EncodableMap>(out)) {
    return {};
  }
  return std::get<EncodableMap>(out);
}

static std::wstring TestApplicationSupportPath() {
  const DWORD required_size =
      GetEnvironmentVariableW(L"APPDATA", nullptr, 0);
  if (required_size == 0) return {};
  std::wstring appdata(required_size, L'\0');
  const DWORD written = GetEnvironmentVariableW(
      L"APPDATA", appdata.data(), required_size);
  if (written == 0 || written >= required_size) return {};
  appdata.resize(written);
  return appdata + L"\\placeholder_company\\placeholder_product";
}

static std::wstring TestStorageFile(const std::string& key) {
  const std::string stored_key = GetStoragePrefixForTesting() + key;
  return TestApplicationSupportPath() + L"\\" +
         std::wstring(stored_key.begin(), stored_key.end()) + L".secure";
}

static void AssertTestPrefixIsIsolated() {
  const auto& test_prefix = GetStoragePrefixForTesting();
  const auto& production_prefix = GetProductionStoragePrefixForTesting();
  ASSERT_FALSE(test_prefix.empty());
  ASSERT_NE(test_prefix, production_prefix);
  ASSERT_EQ(test_prefix.find("FlClash"), std::string::npos);
  ASSERT_EQ(test_prefix.rfind("fss_native_test_", 0), 0u);
  ASSERT_GE(test_prefix.size(), 32u);
}

static void ExpectNoTrackedNativeResources() {
  const auto counts = GetNativeResourceCountsForTesting();
  EXPECT_EQ(counts.known_folder_paths, 0);
  EXPECT_EQ(counts.credential_buffers, 0);
  EXPECT_EQ(counts.find_handles, 0);
  EXPECT_EQ(counts.algorithm_handles, 0);
  EXPECT_EQ(counts.key_handles, 0);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

class FlutterSecureStorageWindowsPluginTest : public ::testing::Test {
 protected:
  void SetUp() override {
    AssertTestPrefixIsIsolated();
    DeleteAll(plugin_);
  }
  void TearDown() override {
    DeleteAll(plugin_);
    ExpectNoTrackedNativeResources();
  }

  FlutterSecureStorageWindowsPlugin plugin_;
};

TEST_F(FlutterSecureStorageWindowsPluginTest, WriteAndReadRoundTrip) {
  ASSERT_TRUE(Write(plugin_, "key1", "value1"));
  EXPECT_EQ(Read(plugin_, "key1"), "value1");
}

TEST_F(FlutterSecureStorageWindowsPluginTest, ReadMissingKeyReturnsNullopt) {
  EXPECT_EQ(Read(plugin_, "nonexistent"), std::nullopt);
}

TEST_F(FlutterSecureStorageWindowsPluginTest, OverwriteReturnsNewValue) {
  Write(plugin_, "k", "first");
  Write(plugin_, "k", "second");
  EXPECT_EQ(Read(plugin_, "k"), "second");
}

TEST_F(FlutterSecureStorageWindowsPluginTest, ContainsKeyTrueAfterWrite) {
  Write(plugin_, "k", "v");
  EXPECT_TRUE(ContainsKey(plugin_, "k"));
}

TEST_F(FlutterSecureStorageWindowsPluginTest, ContainsKeyFalseForMissing) {
  EXPECT_FALSE(ContainsKey(plugin_, "nonexistent"));
}

TEST_F(FlutterSecureStorageWindowsPluginTest, DeleteRemovesKey) {
  Write(plugin_, "k", "v");
  ASSERT_TRUE(ContainsKey(plugin_, "k"));
  Delete(plugin_, "k");
  EXPECT_FALSE(ContainsKey(plugin_, "k"));
}

TEST_F(FlutterSecureStorageWindowsPluginTest, DeleteNonexistentIsNoOp) {
  EXPECT_TRUE(Delete(plugin_, "never_written"));
}

TEST_F(FlutterSecureStorageWindowsPluginTest, DeleteAllClearsAllKeys) {
  Write(plugin_, "a", "1");
  Write(plugin_, "b", "2");
  DeleteAll(plugin_);
  EXPECT_FALSE(ContainsKey(plugin_, "a"));
  EXPECT_FALSE(ContainsKey(plugin_, "b"));
}

TEST_F(FlutterSecureStorageWindowsPluginTest,
       RepeatedOperationsReleaseEveryNativeResource) {
  constexpr int kIterations = 2048;
  for (int i = 0; i < kIterations; ++i) {
    ASSERT_TRUE(Write(plugin_, "resource_loop", "value"));
    ASSERT_EQ(Read(plugin_, "resource_loop"), "value");
    ASSERT_TRUE(ContainsKey(plugin_, "resource_loop"));
    ASSERT_TRUE(DeleteAll(plugin_));
  }
  ExpectNoTrackedNativeResources();
}

TEST_F(FlutterSecureStorageWindowsPluginTest,
       TruncatedEncryptedFileReleasesAlgorithmHandle) {
  ASSERT_TRUE(Write(plugin_, "truncated", "value"));
  const auto file_path = TestStorageFile("truncated");
  ASSERT_FALSE(file_path.empty());
  {
    std::ofstream stream(file_path, std::ios::binary | std::ios::trunc);
    ASSERT_TRUE(stream.good());
    stream.put('\0');
  }

  EXPECT_EQ(Read(plugin_, "truncated"), std::nullopt);
  ExpectNoTrackedNativeResources();
}

TEST_F(FlutterSecureStorageWindowsPluginTest,
       DeleteAllFailureReleasesFindHandle) {
  const std::wstring directory =
      TestApplicationSupportPath() + L"\\" +
      std::wstring(GetStoragePrefixForTesting().begin(),
                   GetStoragePrefixForTesting().end()) +
      L"directory.secure";
  ASSERT_TRUE(CreateDirectoryW(directory.c_str(), nullptr) ||
              GetLastError() == ERROR_ALREADY_EXISTS);

  EXPECT_FALSE(DeleteAll(plugin_));
  ExpectNoTrackedNativeResources();
  ASSERT_TRUE(RemoveDirectoryW(directory.c_str()));
}

TEST_F(FlutterSecureStorageWindowsPluginTest,
       LegacyCredentialBuffersAreReleasedAndDeleteAllStillRunsWithoutFiles) {
  const std::wstring target_name(
      GetStoragePrefixForTesting().begin(),
      GetStoragePrefixForTesting().end());
  const std::wstring legacy_target_name = target_name + L"legacy";
  std::string value = "legacy-value";
  CREDENTIALW credential{};
  credential.Type = CRED_TYPE_GENERIC;
  credential.TargetName = const_cast<wchar_t*>(legacy_target_name.c_str());
  credential.CredentialBlobSize = static_cast<DWORD>(value.size() + 1);
  credential.CredentialBlob = reinterpret_cast<LPBYTE>(value.data());
  credential.Persist = CRED_PERSIST_SESSION;
  ASSERT_TRUE(CredWriteW(&credential, 0));

  EXPECT_TRUE(ContainsKey(plugin_, "legacy"));
  EXPECT_EQ(Read(plugin_, "legacy"), value);
  const auto all = ReadAll(plugin_);
  const auto found = all.find(EncodableValue("legacy"));
  ASSERT_NE(found, all.end());
  EXPECT_EQ(std::get<std::string>(found->second), value);
  ExpectNoTrackedNativeResources();

  ASSERT_TRUE(DeleteAll(plugin_));
  PCREDENTIALW raw_credential = nullptr;
  EXPECT_FALSE(CredReadW(legacy_target_name.c_str(), CRED_TYPE_GENERIC, 0,
                         &raw_credential));
  EXPECT_EQ(GetLastError(), ERROR_NOT_FOUND);
  ExpectNoTrackedNativeResources();
}

TEST_F(FlutterSecureStorageWindowsPluginTest, UnknownMethodReturnsNotImplemented) {
  bool not_implemented_called = false;
  plugin_.HandleMethodCall(
      MethodCall("unknownMethod",
                 std::make_unique<EncodableValue>(EncodableMap{})),
      std::make_unique<MethodResultFunctions<>>(
          /*on_success=*/nullptr,
          /*on_error=*/nullptr,
          [&not_implemented_called]() { not_implemented_called = true; }));
  EXPECT_TRUE(not_implemented_called);
}

TEST_F(FlutterSecureStorageWindowsPluginTest, MissingArgumentsReturnsError) {
  bool error_called = false;
  plugin_.HandleMethodCall(
      MethodCall<EncodableValue>("write", std::unique_ptr<EncodableValue>{}),
      std::make_unique<MethodResultFunctions<>>(
          /*on_success=*/nullptr,
          [&error_called](const std::string&, const std::string& message,
                          const EncodableValue*) {
            error_called = true;
            EXPECT_EQ(message, "write");
          },
          /*on_not_implemented=*/nullptr));
  EXPECT_TRUE(error_called);
}

}  // namespace test
}  // namespace flutter_secure_storage_windows
