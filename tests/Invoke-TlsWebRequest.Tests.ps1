#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Invoke-TlsWebRequest",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    InModuleScope dbatools {
        BeforeAll {
            if (-not ("InvokeTlsWebRequestTest.ProxyWithoutAddress" -as [type])) {
                Add-Type -TypeDefinition @"
using System;
using System.Net;

namespace InvokeTlsWebRequestTest {
    public class ProxyWithoutAddress : IWebProxy {
        public ICredentials Credentials { get; set; }
        public Uri ProxyUri { get; set; }

        public ProxyWithoutAddress(string proxyUri) {
            ProxyUri = new Uri(proxyUri);
        }

        public Uri GetProxy(Uri destination) {
            return ProxyUri;
        }

        public bool IsBypassed(Uri host) {
            return false;
        }
    }
}
"@
            }

            $originalDefaultWebProxy = [System.Net.WebRequest]::DefaultWebProxy
        }

        AfterEach {
            [System.Net.WebRequest]::DefaultWebProxy = $originalDefaultWebProxy
        }

        AfterAll {
            [System.Net.WebRequest]::DefaultWebProxy = $originalDefaultWebProxy
        }

        Context "Proxy auto-detection" {
            BeforeEach {
                Mock Get-DbatoolsConfigValue { $false } -ParameterFilter { $FullName -eq "commands.invoke-tlswebrequest.disableautoproxy" }
                Mock Invoke-WebRequest { "ok" }
            }

            It "Should not replace a configured proxy that has no Address property" {
                $configuredProxyCredentials = New-Object System.Net.NetworkCredential("proxyuser", "proxypass")
                $configuredProxy = New-Object -TypeName "InvokeTlsWebRequestTest.ProxyWithoutAddress" -ArgumentList "http://configured-proxy:8080"
                $configuredProxy.Credentials = $configuredProxyCredentials
                [System.Net.WebRequest]::DefaultWebProxy = $configuredProxy

                Invoke-TlsWebRequest -Uri "https://example.com"

                [object]::ReferenceEquals([System.Net.WebRequest]::DefaultWebProxy, $configuredProxy) | Should -Be $true
                [object]::ReferenceEquals([System.Net.WebRequest]::DefaultWebProxy.Credentials, $configuredProxyCredentials) | Should -Be $true
            }

            It "Should not overwrite the default proxy when -Proxy is supplied" {
                $configuredProxyCredentials = New-Object System.Net.NetworkCredential("proxyuser", "proxypass")
                $configuredProxy = New-Object -TypeName "InvokeTlsWebRequestTest.ProxyWithoutAddress" -ArgumentList "http://configured-proxy:8080"
                $configuredProxy.Credentials = $configuredProxyCredentials
                [System.Net.WebRequest]::DefaultWebProxy = $configuredProxy

                Invoke-TlsWebRequest -Uri "https://example.com" -Proxy "http://override-proxy:8080"

                [object]::ReferenceEquals([System.Net.WebRequest]::DefaultWebProxy, $configuredProxy) | Should -Be $true
                [object]::ReferenceEquals([System.Net.WebRequest]::DefaultWebProxy.Credentials, $configuredProxyCredentials) | Should -Be $true
            }
        }
    }
}
