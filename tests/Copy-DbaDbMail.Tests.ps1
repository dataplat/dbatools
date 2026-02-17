#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaDbMail",
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
                "Credential",
                "Type",
                "Force",
                "ExcludePassword",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # TODO: Maybe remove "-EnableException:$false -WarningAction SilentlyContinue" when we can rely on the setting beeing 0 when entering the test
        $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Name "Database Mail XPs" -Value 1 -EnableException:$false -WarningAction SilentlyContinue

        $accountName = "dbatoolsci_test_$(Get-Random)"
        $profileName = "dbatoolsci_test_$(Get-Random)"

        $splatAccount = @{
            SqlInstance    = $TestConfig.InstanceCopy1
            Name           = $accountName
            Description    = "Mail account for email alerts"
            EmailAddress   = "dbatoolssci@dbatools.io"
            DisplayName    = "dbatoolsci mail alerts"
            ReplyToAddress = "no-reply@dbatools.io"
            MailServer     = "smtp.dbatools.io"
        }
        $null = New-DbaDbMailAccount @splatAccount -Force

        $splatProfile = @{
            SqlInstance         = $TestConfig.InstanceCopy1
            Name                = $profileName
            Description         = "Mail profile for email alerts"
            MailAccountName     = $accountName
            MailAccountPriority = 1
        }
        $null = New-DbaDbMailProfile @splatProfile

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Query "EXEC msdb.dbo.sysmail_delete_account_sp @account_name = '$accountName';"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Query "EXEC msdb.dbo.sysmail_delete_profile_sp @profile_name = '$profileName';"

        $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Name "Database Mail XPs" -Value 0

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying DbMail" {
        BeforeAll {
            $results = Copy-DbaDbMail -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -OutVariable "global:dbatoolsciOutput"
        }

        It "Should have copied database mail items" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have copied Mail Configuration from source to destination" {
            $result = $results | Where-Object { $_.Type -eq "Mail Configuration" -and $_.Name -eq "Server Configuration" }
            $result.SourceServer | Should -Be $TestConfig.InstanceCopy1
            $result.DestinationServer | Should -Be $TestConfig.InstanceCopy2
            $result.Status | Should -Be "Successful"
        }

        It "Should have copied Mail Account from source to destination" {
            $result = $results | Where-Object Type -eq "Mail Account"
            $result.SourceServer | Should -Be $TestConfig.InstanceCopy1
            $result.DestinationServer | Should -Be $TestConfig.InstanceCopy2
            $result.Status | Should -Be "Successful"
        }

        It "Should have copied Mail Profile from source to destination" {
            $result = $results | Where-Object Type -eq "Mail Profile"
            $result.SourceServer | Should -Be $TestConfig.InstanceCopy1
            $result.DestinationServer | Should -Be $TestConfig.InstanceCopy2
            $result.Status | Should -Be "Successful"
        }

        It "Should have copied Mail Server from source to destination" {
            $result = $results | Where-Object Type -eq "Mail Server"
            $result.SourceServer | Should -Be $TestConfig.InstanceCopy1
            $result.DestinationServer | Should -Be $TestConfig.InstanceCopy2
            $result.Status | Should -Be "Successful"
        }
    }

    Context "When copying MailServers specifically" {
        BeforeAll {
            $results = Copy-DbaDbMail -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Type MailServers
        }

        It "Should have returned results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have not reported on Mail Configuration" {
            $result = $results | Where-Object Type -eq "Mail Configuration"
            $result | Should -BeNullOrEmpty
        }

        It "Should have not reported on Mail Account" {
            $result = $results | Where-Object Type -eq "Mail Account"
            $result | Should -BeNullOrEmpty
        }

        It "Should have not reported on Mail Profile" {
            $result = $results | Where-Object Type -eq "Mail Profile"
            $result | Should -BeNullOrEmpty
        }

        It "Should have skipped Mail Server" {
            $result = $results | Where-Object Type -eq "Mail Server"
            $result.SourceServer | Should -Be $TestConfig.InstanceCopy1
            $result.DestinationServer | Should -Be $TestConfig.InstanceCopy2
            $result.Status | Should -Be "Skipped"
        }
    }

    Context "When Database Mail XPs status is reported" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name "Database Mail XPs" -Value 0
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $results = Copy-DbaDbMail -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Force
        }

        It "Should report Database Mail XPs status" {
            $result = $results | Where-Object Name -eq "Database Mail XPs"
            $result | Should -Not -BeNullOrEmpty
            $result.Type | Should -Be "Mail Configuration"
        }

        It "Should have enabled Database Mail XPs on destination" {
            $result = $results | Where-Object Name -eq "Database Mail XPs"
            $result.Status | Should -Be "Successful"
            $result.Notes | Should -Match "enabled"
        }

        It "Should verify Database Mail XPs is enabled on destination" {
            $destConfig = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceCopy2 -Name "Database Mail XPs"
            $destConfig.ConfiguredValue | Should -Be 1
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            if (-not $global:dbatoolsciOutput) {
                Set-ItResult -Skipped -Because "no output was captured"
                return
            }
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the custom dbatools type name" {
            if (-not $global:dbatoolsciOutput) {
                Set-ItResult -Skipped -Because "no output was captured"
                return
            }
            $global:dbatoolsciOutput[0].PSObject.TypeNames[0] | Should -Be "dbatools.MigrationObject"
        }

        It "Should have the correct default display columns" {
            if (-not $global:dbatoolsciOutput) {
                Set-ItResult -Skipped -Because "no output was captured"
                return
            }
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