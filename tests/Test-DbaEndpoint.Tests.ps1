#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaEndpoint",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Endpoint",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $script:endpointSuffix = [guid]::NewGuid().ToString("N")
        $script:endpointNames = @("dbatoolsci_TSqlA_$script:endpointSuffix", "dbatoolsci_TSqlB_$script:endpointSuffix")
        $script:createdEndpoints = @()
        $script:createdEndpointNames = @()
        $script:attemptedPorts = @()
        $queryPorts = "SELECT port FROM sys.tcp_endpoints WHERE port IS NOT NULL;"
        $usedPorts = @(Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query $queryPorts | Select-Object -ExpandProperty port)

        try {
            for ($attempt = 0; $attempt -lt 8 -and $script:createdEndpoints.Count -lt 2; $attempt++) {
                $port = Get-Random -Minimum 50000 -Maximum 60000
                if ($port -in $usedPorts -or $port -in $script:attemptedPorts -or (Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue)) { continue }
                $script:attemptedPorts += $port
                $splatEndpoint = @{ SqlInstance = $TestConfig.InstanceSingle; Type = "TSql"; Name = $script:endpointNames[$script:createdEndpoints.Count]; Port = $port; EnableException = $true }
                try {
                    $script:createdEndpoints += New-DbaEndpoint @splatEndpoint | Start-DbaEndpoint -EnableException
                } catch {
                    if ($_.Exception.Message -notmatch "bindings specified|0x800700b7") { throw }
                }
            }
            $script:createdEndpointNames = @($script:createdEndpoints | Select-Object -ExpandProperty Name)
            $script:createdEndpointNames.Count | Should -Be 2

            $queryBoundEndpoint = @"
SELECT e.name
FROM sys.tcp_endpoints AS t
JOIN sys.endpoints AS e ON e.endpoint_id = t.endpoint_id
JOIN sys.dm_exec_connections AS c ON c.local_tcp_port = t.port
WHERE t.port <> 0 AND c.local_tcp_port IS NOT NULL
GROUP BY e.name;
"@
            $script:boundEndpointNames = @(Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query $queryBoundEndpoint | Select-Object -ExpandProperty name)
            $script:boundEndpointNames.Count | Should -Be 1
        } catch {
            foreach ($name in $script:createdEndpointNames) {
                Remove-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint $name -EnableException | Out-Null
            }
            $script:createdEndpointNames = @()
            throw
        } finally {
            $splatGrant = @{ SqlInstance = $TestConfig.InstanceSingle; Database = "master"; Query = "GRANT CONNECT ON ENDPOINT::[TSQL Default TCP] TO [public];"; EnableException = $true }
            Invoke-DbaQuery @splatGrant | Out-Null
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        foreach ($name in $script:createdEndpointNames) {
            $splatRemove = @{ SqlInstance = $TestConfig.InstanceSingle; Endpoint = $name; EnableException = $true }
            Remove-DbaEndpoint @splatRemove | Out-Null
        }
        $splatGrant = @{ SqlInstance = $TestConfig.InstanceSingle; Database = "master"; Query = "GRANT CONNECT ON ENDPOINT::[TSQL Default TCP] TO [public];"; EnableException = $true }
        Invoke-DbaQuery @splatGrant | Out-Null

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "returns success for the bound endpoint" {
        $results = @(Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint $script:boundEndpointNames -EnableException | Test-DbaEndpoint)
        $results.Count | Should -Be 1
        $results.Endpoint | Should -Be $script:boundEndpointNames[0]
        $results.Connection | Should -Be 'Success'
    }

    It "returns attributable failures for two piped TSql endpoints" {
        $splatGet = @{ SqlInstance = $TestConfig.InstanceSingle; Endpoint = $script:createdEndpointNames; EnableException = $true }
        $results = @(Get-DbaEndpoint @splatGet | Test-DbaEndpoint)
        $results.Count | Should -Be 2
        @($results | Where-Object Connection -eq "Success").Count | Should -Be 0
        @($results.Endpoint | Sort-Object) | Should -Be @($script:createdEndpointNames | Sort-Object)
    }

}
