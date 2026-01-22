#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Sync-DbaLoginPermission",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Login",
                "ExcludeLogin",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $tempguid = [guid]::newguid()
        $DBUserName = "dbatoolssci_$($tempguid.guid)"
        $CreateTestUser = @"
CREATE LOGIN [$DBUserName]
    WITH PASSWORD = '$($tempguid.guid)';
USE Master;
CREATE USER [$DBUserName] FOR LOGIN [$DBUserName]
    WITH DEFAULT_SCHEMA = dbo;
GRANT VIEW ANY DEFINITION to [$DBUserName];
"@
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Query $CreateTestUser -Database master

        # This is used later in the test
        $CreateTestLogin = @"
CREATE LOGIN [$DBUserName]
    WITH PASSWORD = '$($tempguid.guid)';
"@
    }
    AfterAll {
        $DropTestUser = "DROP LOGIN [$DBUserName]"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Query $DropTestUser -Database master
    }

    Context "Command execution and functionality" {

        It "Should not have the user permissions of $DBUserName" {
            $permissionsBefore = Get-DbaUserPermission -SqlInstance $TestConfig.InstanceMulti2 -Database master | Where-Object { $_.member -eq $DBUserName }
            $permissionsBefore | Should -BeNullOrEmpty
        }

        It "Should execute against active nodes" {
            # Creates the user on
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Query $CreateTestLogin
            $results = Sync-DbaLoginPermission -Source $TestConfig.InstanceMulti1 -Destination $TestConfig.InstanceMulti2 -Login $DBUserName -ExcludeLogin 'NotaLogin' -WarningVariable $warn
            $results.Status | Should -Be 'Successful'
            $warn | Should -BeNullOrEmpty
        }

        # The copy failes on Appveyor with: Failed to create or use STIG schema on APPVYR-WIN\sql2017
        It "Should have copied the user permissions of $DBUserName" -Skip:$env:appveyor {
            $permissionsAfter = Get-DbaUserPermission -SqlInstance $TestConfig.InstanceMulti2 -Database master | Where-Object { $_.member -eq $DBUserName -and $_.permission -eq 'VIEW ANY DEFINITION' }
            $permissionsAfter.member | Should -Be $DBUserName
        }
    }

    Context "Login state synchronization" {
        BeforeAll {
            $tempLoginGuid = [guid]::newguid()
            $stateTestLogin = "dbatoolssci_state_$($tempLoginGuid.guid)"
            $createStateLogin = @"
CREATE LOGIN [$stateTestLogin]
    WITH PASSWORD = '$($tempLoginGuid.guid)';
"@
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Query $createStateLogin
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Query $createStateLogin

            # Disable and deny connect on source
            $splatDisable = @{
                SqlInstance = $TestConfig.InstanceMulti1
                Query       = "ALTER LOGIN [$stateTestLogin] DISABLE; DENY CONNECT SQL TO [$stateTestLogin];"
            }
            Invoke-DbaQuery @splatDisable
        }
        AfterAll {
            $dropStateLogin = "DROP LOGIN [$stateTestLogin]"
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Query $dropStateLogin -Database master
        }

        It "Should sync login disabled state from source to destination" {
            $sourceLogin = Get-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login $stateTestLogin
            $sourceLogin.IsDisabled | Should -Be $true

            $destLoginBefore = Get-DbaLogin -SqlInstance $TestConfig.InstanceMulti2 -Login $stateTestLogin
            $destLoginBefore.IsDisabled | Should -Be $false

            $splatSync = @{
                Source      = $TestConfig.InstanceMulti1
                Destination = $TestConfig.InstanceMulti2
                Login       = $stateTestLogin
            }
            $results = Sync-DbaLoginPermission @splatSync
            $results.Status | Should -Be "Successful"

            $destLoginAfter = Get-DbaLogin -SqlInstance $TestConfig.InstanceMulti2 -Login $stateTestLogin
            $destLoginAfter.IsDisabled | Should -Be $true
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $tempOutputGuid = [guid]::newguid()
            $outputTestLogin = "dbatoolssci_output_$($tempOutputGuid.guid)"
            $createOutputLogin = @"
CREATE LOGIN [$outputTestLogin]
    WITH PASSWORD = '$($tempOutputGuid.guid)';
"@
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Query $createOutputLogin
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Query $createOutputLogin

            $splatSyncOutput = @{
                Source            = $TestConfig.InstanceMulti1
                Destination       = $TestConfig.InstanceMulti2
                Login             = $outputTestLogin
                EnableException   = $true
            }
            $result = Sync-DbaLoginPermission @splatSyncOutput
        }
        AfterAll {
            $dropOutputLogin = "DROP LOGIN [$outputTestLogin]"
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Query $dropOutputLogin -Database master
        }

        It "Returns PSCustomObject with MigrationObject type" {
            $result.PSObject.TypeNames | Should -Contain 'MigrationObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'DateTime',
                'SourceServer',
                'DestinationServer',
                'Name',
                'Type',
                'Status',
                'Notes'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has Status property with valid value" {
            $result.Status | Should -BeIn @('Successful', 'Failed')
        }

        It "Has Type property set to 'Login Permissions'" {
            $result.Type | Should -Be 'Login Permissions'
        }
    }
}