using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Connection.Test
{
    /// <summary>
    /// Pure-logic coverage for the HTTP token service New-DbaAzAccessToken and Connect-DbaInstance share: request
    /// URIs and bodies, token and error parsing, and configuration reads. The requests themselves run in the lab.
    /// </summary>
    [TestClass]
    public class AzureAccessTokenServiceTest
    {
        [TestMethod]
        public void BuildManagedIdentityUri_DefaultsTheApiVersionAndEncodesTheResource()
        {
            string uri = AzureAccessTokenService.BuildManagedIdentityUri("https://database.windows.net/", null);
            Assert.AreEqual("http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-04-02&resource=https%3A%2F%2Fdatabase.windows.net%2F", uri);
        }

        [TestMethod]
        public void BuildManagedIdentityUri_UsesAGivenApiVersion()
        {
            string uri = AzureAccessTokenService.BuildManagedIdentityUri("https://vault.azure.net/", "2019-08-01");
            StringAssert.Contains(uri, "api-version=2019-08-01&");
        }

        [TestMethod]
        public void BuildTokenEndpoint_JoinsAuthorityAndTenant()
        {
            Assert.AreEqual("https://login.microsoftonline.com/contoso.onmicrosoft.com/oauth2/token",
                AzureAccessTokenService.BuildTokenEndpoint("https://login.microsoftonline.com/", "contoso.onmicrosoft.com"));
            Assert.AreEqual("https://login.windows.net/tenant/oauth2/token",
                AzureAccessTokenService.BuildTokenEndpoint("https://login.windows.net", "tenant"));
        }

        [TestMethod]
        public void BuildTokenEndpoint_EncodesTheTenant()
        {
            StringAssert.Contains(AzureAccessTokenService.BuildTokenEndpoint("https://login.windows.net/", "a/b?c"), "/a%2Fb%3Fc/oauth2/token");
        }

        [TestMethod]
        public void BuildClientCredentialBody_EncodesEveryValue()
        {
            string body = AzureAccessTokenService.BuildClientCredentialBody("app id", "s&e=c+r/t", "https://database.windows.net/");
            Assert.AreEqual("grant_type=client_credentials&client_id=app%20id&client_secret=s%26e%3Dc%2Br%2Ft&resource=https%3A%2F%2Fdatabase.windows.net%2F", body);
        }

        [TestMethod]
        public void ParseTokenResponse_ReadsExpiresOnAsAString()
        {
            AzureAccessToken token = AzureAccessTokenService.ParseTokenResponse("{\"access_token\":\"abc\",\"expires_in\":\"3599\",\"expires_on\":\"1506484173\",\"token_type\":\"Bearer\"}");
            Assert.AreEqual("abc", token.AccessToken);
            Assert.AreEqual(DateTimeOffset.FromUnixTimeSeconds(1506484173), token.ExpiresOn);
        }

        [TestMethod]
        public void ParseTokenResponse_ReadsExpiresOnAsANumber()
        {
            AzureAccessToken token = AzureAccessTokenService.ParseTokenResponse("{\"access_token\":\"abc\",\"expires_on\":1506484173}");
            Assert.AreEqual(DateTimeOffset.FromUnixTimeSeconds(1506484173), token.ExpiresOn);
        }

        [TestMethod]
        public void ParseTokenResponse_FallsBackToExpiresIn()
        {
            DateTimeOffset before = DateTimeOffset.UtcNow;
            AzureAccessToken token = AzureAccessTokenService.ParseTokenResponse("{\"access_token\":\"abc\",\"expires_in\":3599}");
            Assert.IsTrue(token.ExpiresOn >= before.AddSeconds(3599));
            Assert.IsTrue(token.ExpiresOn <= DateTimeOffset.UtcNow.AddSeconds(3599));
        }

        [TestMethod]
        public void ParseTokenResponse_RefusesAResponseWithoutAToken()
        {
            bool threw = false;
            try
            {
                AzureAccessTokenService.ParseTokenResponse("{\"token_type\":\"Bearer\"}");
            }
            catch (InvalidOperationException)
            {
                threw = true;
            }
            Assert.IsTrue(threw);
        }

        [TestMethod]
        public void ParseErrorResponse_PrefersTheDescription()
        {
            string description = AzureAccessTokenService.ParseErrorResponse("{\"error\":\"invalid_request\",\"error_description\":\"AADSTS90002: Tenant 'x' not found.\"}");
            Assert.AreEqual("AADSTS90002: Tenant 'x' not found.", description);
            Assert.AreEqual("invalid_client", AzureAccessTokenService.ParseErrorResponse("{\"error\":\"invalid_client\"}"));
        }

        [TestMethod]
        public void ParseErrorResponse_ReturnsNullForABodyThatIsNotAnOAuthError()
        {
            Assert.IsNull(AzureAccessTokenService.ParseErrorResponse("<html>Bad gateway</html>"));
            Assert.IsNull(AzureAccessTokenService.ParseErrorResponse(""));
            Assert.IsNull(AzureAccessTokenService.ParseErrorResponse("[1,2]"));
        }

        [TestMethod]
        public void ReadConfigValue_ReadsAHashtableKeyWithoutCase()
        {
            Hashtable config = new Hashtable();
            config["resource"] = "https://vault.azure.net/";
            Assert.AreEqual("https://vault.azure.net/", AzureAccessTokenService.ReadConfigValue(config, "Resource"));
            Assert.IsNull(AzureAccessTokenService.ReadConfigValue(config, "Version"));
        }

        [TestMethod]
        public void ReadConfigValue_ReadsAPropertyOfAnObject()
        {
            PSObject config = new PSObject();
            config.Properties.Add(new PSNoteProperty("Version", "2019-08-01"));
            Assert.AreEqual("2019-08-01", AzureAccessTokenService.ReadConfigValue(config, "Version"));
            Assert.IsNull(AzureAccessTokenService.ReadConfigValue(null, "Version"));
        }
    }
}
