param($ModuleName = 'dbatools')

Describe "Set-DbatoolsConfig" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbatoolsConfig
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "FullName",
                "Module",
                "Name",
                "Value",
                "PersistedValue",
                "PersistedType",
                "Description",
                "Validation",
                "Handler",
                "Hidden",
                "Default",
                "Initialize",
                "SimpleExport",
                "ModuleExport",
                "DisableValidation",
                "DisableHandler",
                "PassThru",
                "Register",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}

Describe "Set-DbatoolsConfig Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    It "impacts the connection timeout" {
        $null = Set-DbatoolsConfig -FullName sql.connection.timeout -Value 60
        $results = New-DbaConnectionString -SqlInstance test -Database dbatools -ConnectTimeout ([Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout)
        $results | Should -Match 'Connect Timeout=60'
    }
}
