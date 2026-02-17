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
            $splatSync = @{
                Source       = $TestConfig.InstanceMulti1
                Destination  = $TestConfig.InstanceMulti2
                Login        = $DBUserName
                ExcludeLogin = "NotaLogin"
            }
            $results = Sync-DbaLoginPermission @splatSync -OutVariable "global:dbatoolsciOutput" -WarningVariable $warn
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

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should have the custom dbatools type name" {
            $global:dbatoolsciOutput[0].PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "SourceServer",
                "DestinationServer",
                "Name",
                "Type",
                "Status",
                "Notes",
                "DateTime"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "DateTime",
                "SourceServer",
                "DestinationServer",
                "Name",
                "Type",
                "Status",
                "Notes"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}