using System;
using System.Collections;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Net;
using System.Text;
using System.Text.Json;

namespace Dataplat.Dbatools.Connection
{
    /// <summary>
    /// An OAuth2 access token and the moment it expires.
    /// </summary>
    public sealed class AzureAccessToken
    {
        /// <summary>Creates a token record.</summary>
        /// <param name="accessToken">The bearer token text</param>
        /// <param name="expiresOn">When the token expires</param>
        public AzureAccessToken(string accessToken, DateTimeOffset expiresOn)
        {
            AccessToken = accessToken;
            ExpiresOn = expiresOn;
        }

        /// <summary>The bearer token text.</summary>
        public string AccessToken { get; private set; }

        /// <summary>When the token expires.</summary>
        public DateTimeOffset ExpiresOn { get; private set; }
    }

    /// <summary>
    /// Requests OAuth2 access tokens over plain HTTP from Microsoft Entra ID (client credentials) and from the Azure
    /// Instance Metadata Service (managed identity), without ADAL, MSAL or PowerShell. New-DbaAzAccessToken and its
    /// renewable token use it. The requests are synchronous because the runtime avoids async code.
    /// </summary>
    public static class AzureAccessTokenService
    {
        /// <summary>The managed identity token endpoint of the Azure Instance Metadata Service.</summary>
        public const string ManagedIdentityEndpoint = "http://169.254.169.254/metadata/identity/oauth2/token";

        /// <summary>The api-version New-DbaAzAccessToken sends when its configuration names none.</summary>
        public const string DefaultManagedIdentityApiVersion = "2018-04-02";

        /// <summary>The Microsoft Entra ID authority service principal tokens and the renewable token ask.</summary>
        public const string Authority = "https://login.microsoftonline.com/";

        /// <summary>How long a managed identity request may take, in milliseconds.</summary>
        public const int ManagedIdentityTimeoutMilliseconds = 30000;

        /// <summary>
        /// Gets a token for a resource from the Azure Instance Metadata Service, as the managed identity of the machine.
        /// </summary>
        /// <param name="resource">The App ID URI of the resource, such as https://database.windows.net/</param>
        /// <param name="apiVersion">The IMDS api-version; empty uses the default</param>
        /// <returns>The token</returns>
        public static AzureAccessToken GetManagedIdentityToken(string resource, string apiVersion)
        {
            HttpWebRequest request = CreateRequest(BuildManagedIdentityUri(resource, apiVersion), "GET");
            request.Headers["Metadata"] = "true";
            // Microsoft Learn: IMDS isn't intended to be used behind a proxy, and doing so is unsupported.
            request.Proxy = null;
            request.Timeout = ManagedIdentityTimeoutMilliseconds;
            return ParseTokenResponse(Send(request, null));
        }

        /// <summary>
        /// Gets a token for a resource with the OAuth2 client credentials grant of a service principal.
        /// </summary>
        /// <param name="authority">The authority, such as https://login.microsoftonline.com/</param>
        /// <param name="tenant">The tenant id or domain name</param>
        /// <param name="clientId">The application (client) id</param>
        /// <param name="clientSecret">The client secret</param>
        /// <param name="resource">The App ID URI of the resource</param>
        /// <returns>The token</returns>
        public static AzureAccessToken GetClientCredentialToken(string authority, string tenant, string clientId, string clientSecret, string resource)
        {
            HttpWebRequest request = CreateRequest(BuildTokenEndpoint(authority, tenant), "POST");
            request.ContentType = "application/x-www-form-urlencoded";
            byte[] body = Encoding.UTF8.GetBytes(BuildClientCredentialBody(clientId, clientSecret, resource));
            return ParseTokenResponse(Send(request, body));
        }

        /// <summary>Builds the IMDS token request URI.</summary>
        /// <param name="resource">The App ID URI of the resource</param>
        /// <param name="apiVersion">The IMDS api-version; empty uses the default</param>
        /// <returns>The request URI</returns>
        public static string BuildManagedIdentityUri(string resource, string apiVersion)
        {
            string version = String.IsNullOrEmpty(apiVersion) ? DefaultManagedIdentityApiVersion : apiVersion;
            return String.Format(CultureInfo.InvariantCulture, "{0}?api-version={1}&resource={2}",
                ManagedIdentityEndpoint, Uri.EscapeDataString(version), Uri.EscapeDataString(resource ?? String.Empty));
        }

        /// <summary>Builds the version 1 token endpoint of a tenant, which takes a resource rather than a scope.</summary>
        /// <param name="authority">The authority, with or without a trailing slash</param>
        /// <param name="tenant">The tenant id or domain name</param>
        /// <returns>The token endpoint</returns>
        public static string BuildTokenEndpoint(string authority, string tenant)
        {
            return String.Format(CultureInfo.InvariantCulture, "{0}/{1}/oauth2/token",
                (authority ?? String.Empty).TrimEnd('/'), Uri.EscapeDataString(tenant ?? String.Empty));
        }

        /// <summary>Builds the form body of a client credentials request, every value URL-encoded.</summary>
        /// <param name="clientId">The application (client) id</param>
        /// <param name="clientSecret">The client secret</param>
        /// <param name="resource">The App ID URI of the resource</param>
        /// <returns>The form body</returns>
        public static string BuildClientCredentialBody(string clientId, string clientSecret, string resource)
        {
            return String.Format(CultureInfo.InvariantCulture, "grant_type=client_credentials&client_id={0}&client_secret={1}&resource={2}",
                Uri.EscapeDataString(clientId ?? String.Empty),
                Uri.EscapeDataString(clientSecret ?? String.Empty),
                Uri.EscapeDataString(resource ?? String.Empty));
        }

        /// <summary>
        /// The exception PowerShell's web cmdlets report for a failed request this service sent. HttpWebRequest on .NET wraps
        /// the transport's HttpRequestException in a WebException, where PowerShell 7's Invoke-WebRequest reports the
        /// HttpRequestException itself; on .NET Framework the WebException is what Windows PowerShell reports.
        /// </summary>
        /// <param name="failure">The exception the request raised</param>
        /// <returns>The exception to report</returns>
        public static Exception ReportedRequestFailure(Exception failure)
        {
#if !NETFRAMEWORK
            if (failure is WebException web && web.InnerException is System.Net.Http.HttpRequestException transport)
                return transport;
#endif
            return failure;
        }

        /// <summary>
        /// Reads access_token and the expiry from a token response. expires_on (Unix seconds, a number or a string) wins;
        /// without it expires_in counts from now.
        /// </summary>
        /// <param name="json">The response body</param>
        /// <returns>The token</returns>
        public static AzureAccessToken ParseTokenResponse(string json)
        {
            using (JsonDocument document = JsonDocument.Parse(json))
            {
                JsonElement root = document.RootElement;
                string accessToken = ReadString(root, "access_token");
                if (String.IsNullOrEmpty(accessToken))
                    throw new InvalidOperationException("The token response did not contain an access_token.");

                long seconds;
                DateTimeOffset expiresOn;
                if (TryReadInt64(root, "expires_on", out seconds))
                    expiresOn = DateTimeOffset.FromUnixTimeSeconds(seconds);
                else if (TryReadInt64(root, "expires_in", out seconds))
                    expiresOn = DateTimeOffset.UtcNow.AddSeconds(seconds);
                else
                    expiresOn = DateTimeOffset.MinValue;
                return new AzureAccessToken(accessToken, expiresOn);
            }
        }

        /// <summary>
        /// Reads error_description, or else error, from an OAuth2 error body; returns null when the body is not one.
        /// </summary>
        /// <param name="json">The response body</param>
        /// <returns>The description, or null</returns>
        public static string ParseErrorResponse(string json)
        {
            if (String.IsNullOrWhiteSpace(json))
                return null;
            try
            {
                using (JsonDocument document = JsonDocument.Parse(json))
                {
                    if (document.RootElement.ValueKind != JsonValueKind.Object)
                        return null;
                    string description = ReadString(document.RootElement, "error_description");
                    if (!String.IsNullOrEmpty(description))
                        return description;
                    string error = ReadString(document.RootElement, "error");
                    return String.IsNullOrEmpty(error) ? null : error;
                }
            }
            catch (JsonException)
            {
                // Not JSON: the caller keeps the HTTP error it already has.
                return null;
            }
        }

        /// <summary>
        /// Reads one value of a configuration object: a key of a dictionary, matched without case, or a property.
        /// </summary>
        /// <param name="config">A hashtable, a dictionary or any object</param>
        /// <param name="name">The key or property name</param>
        /// <returns>The value as a string, or null</returns>
        public static string ReadConfigValue(object config, string name)
        {
            // A PSCustomObject keeps its note properties on the PSObject wrapper, not on the base object.
            PSObject wrapper = config as PSObject;
            object baseObject = wrapper != null ? wrapper.BaseObject : config;
            if (baseObject == null)
                return null;
            IDictionary dictionary = baseObject as IDictionary;
            if (dictionary != null)
            {
                foreach (DictionaryEntry entry in dictionary)
                {
                    if (String.Equals(Convert.ToString(entry.Key, CultureInfo.InvariantCulture), name, StringComparison.OrdinalIgnoreCase))
                        return entry.Value == null ? null : Convert.ToString(entry.Value is PSObject inner ? inner.BaseObject : entry.Value, CultureInfo.InvariantCulture);
                }
                return null;
            }
            PSPropertyInfo property = (wrapper ?? PSObject.AsPSObject(baseObject)).Properties[name];
            if (property == null || property.Value == null)
                return null;
            return Convert.ToString(property.Value is PSObject value ? value.BaseObject : property.Value, CultureInfo.InvariantCulture);
        }

        private static string ReadString(JsonElement root, string name)
        {
            JsonElement value;
            if (!root.TryGetProperty(name, out value))
                return null;
            return value.ValueKind == JsonValueKind.String ? value.GetString() : value.ToString();
        }

        private static bool TryReadInt64(JsonElement root, string name, out long seconds)
        {
            seconds = 0;
            JsonElement value;
            if (!root.TryGetProperty(name, out value))
                return false;
            if (value.ValueKind == JsonValueKind.Number)
                return value.TryGetInt64(out seconds);
            if (value.ValueKind == JsonValueKind.String)
                return Int64.TryParse(value.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out seconds);
            return false;
        }

        private static HttpWebRequest CreateRequest(string uri, string method)
        {
#pragma warning disable SYSLIB0014 // HttpWebRequest is the synchronous HTTP API on both net472 and net8.0; the runtime avoids async code.
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(uri);
#pragma warning restore SYSLIB0014
            request.Method = method;
            request.Accept = "application/json";
            return request;
        }

        private static string Send(HttpWebRequest request, byte[] body)
        {
#if NETFRAMEWORK
            // Invoke-TlsWebRequest, which the pinned managed identity path used, adds TLS 1.2 to an explicit protocol
            // list for the request and puts the caller's value back afterwards. SystemDefault (0) already lets the OS
            // choose.
            SecurityProtocolType previous = ServicePointManager.SecurityProtocol;
            if (previous != SecurityProtocolType.SystemDefault && (previous & SecurityProtocolType.Tls12) == 0)
                ServicePointManager.SecurityProtocol = previous | SecurityProtocolType.Tls12;
            try
            {
#endif
                try
                {
                    if (body != null)
                    {
                        request.ContentLength = body.Length;
                        using (Stream stream = request.GetRequestStream())
                            stream.Write(body, 0, body.Length);
                    }
                    using (WebResponse response = request.GetResponse())
                        return ReadBody(response);
                }
                catch (WebException ex)
                {
                    if (ex.Response == null)
                        throw;
                    string description;
                    using (WebResponse response = ex.Response)
                        description = ParseErrorResponse(ReadBody(response));
                    if (description == null)
                        throw;
                    // No inner exception: dbatools warnings show the innermost message of the chain, which would be
                    // the HTTP status line rather than Microsoft Entra ID's answer.
                    throw new InvalidOperationException(description);
                }
#if NETFRAMEWORK
            }
            finally
            {
                ServicePointManager.SecurityProtocol = previous;
            }
#endif
        }

        private static string ReadBody(WebResponse response)
        {
            using (Stream stream = response.GetResponseStream())
            {
                if (stream == null)
                    return String.Empty;
                using (StreamReader reader = new StreamReader(stream, Encoding.UTF8))
                    return reader.ReadToEnd();
            }
        }
    }
}
