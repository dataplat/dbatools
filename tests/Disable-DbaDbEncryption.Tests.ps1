#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Disable-DbaDbEncryption",
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
                "Database",
                "InputObject",
                "NoEncryptionKeyDrop",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:Confirm"] = $false
        $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force

        # Setup master certificate if needed
        $mastercert = Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle -Database master |
            Where-Object Name -notmatch "##" |
            Select-Object -First 1
        if (-not $mastercert) {
            $delmastercert = $true
            $mastercert = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceSingle
        }

        # Create and configure test database
        $testDb = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
        $testDb | New-DbaDbMasterKey -SecurePassword $passwd
        $testDb | New-DbaDbCertificate
        $testDb | New-DbaDbEncryptionKey -Force
        $testDb | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force
    }

    AfterAll {
        if ($testDb) {
            $testDb | Remove-DbaDatabase
        }
        if ($delmastercert) {
            $mastercert | Remove-DbaDbCertificate
        }
    }

    Context "When disabling encryption via pipeline" {
        BeforeAll {
            Start-Sleep -Seconds 10 # Allow encryption to complete
            $results = $testDb | Disable-DbaDbEncryption -NoEncryptionKeyDrop -WarningVariable warn 3> $null
        }

        It "Should complete without warnings" {
            $warn | Where-Object { $_ -NotLike "*Connect-DbaInstance*" } | Should -BeNullOrEmpty
        }

        It "Should disable encryption" {
            $results.EncryptionEnabled | Should -Be $false
        }

        It "Returns output of the documented type" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $results[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Database"
        }

        It "Has the expected default display properties" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DatabaseName",
                "EncryptionEnabled"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has working alias properties" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $results[0].psobject.Properties["DatabaseName"] | Should -Not -BeNullOrEmpty
            $results[0].psobject.Properties["DatabaseName"].MemberType | Should -Be "AliasProperty"
        }
    }

    Context "When disabling encryption via parameters" {
        BeforeAll {
            $null = $testDb | Enable-DbaDbEncryption -EncryptorName $mastercert.Name -Force
            Start-Sleep -Seconds 10 # Allow encryption to complete

            $splatDisable = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $testDb.Name
            }
            $results = Disable-DbaDbEncryption @splatDisable -WarningVariable warn 3> $null
        }

        It "Should complete without warnings" {
            $warn | Where-Object { $_ -NotLike "*Connect-DbaInstance*" } | Should -BeNullOrEmpty
        }

        It "Should disable encryption" {
            $results.EncryptionEnabled | Should -Be $false
        }
    }
}