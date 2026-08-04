#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaLinkedServer",
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
                "LinkedServer",
                "ExcludeLinkedServer",
                "UpgradeSqlClient",
                "ExcludePassword",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # Three source fixtures, because the interesting branches are all provider-shaped.
    #
    # sp_addlinkedserver stores @provider as an opaque string and never checks that the provider is
    # installed, which is what makes two of these possible at all: a linked server naming SQLNCLI10
    # (only SQLNCLI11 is installed anywhere here) gives -UpgradeSqlClient something to actually
    # rewrite, and one naming a provider nothing has gives the missing-provider skip a case. A
    # provider whose name starts with SQLN is deliberately exempt from that skip, so the two cannot
    # be the same fixture.
    #
    # Every leg names what it wants through -LinkedServer. sql2017 carries repl_distributor, which
    # the command refuses to drop, and a neighbouring session can leave more behind; an unfiltered
    # copy would drag all of it to the destination.
    #
    # The destination is reset per leg rather than once, so the legs do not depend on each other's
    # order or on which of them last succeeded.
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2

        $linkedServerWithLogin = "dbatoolsci_ls_login"
        $linkedServerOldClient = "dbatoolsci_ls_oldclient"
        $linkedServerNoProvider = "dbatoolsci_ls_noprovider"
        $fixtureNames = $linkedServerWithLogin, $linkedServerOldClient, $linkedServerNoProvider

        # The destination's newest SQL Native Client, which is what -UpgradeSqlClient rewrites to.
        $newestClientProvider = $destServer.Settings.OleDbProviderSettings |
            Where-Object Name -like "SQLNCLI*" |
            Sort-Object Name -Descending |
            Select-Object -First 1 -ExpandProperty Name

        function Remove-TestLinkedServer {
            param(
                $Server,
                [string]$Name
            )
            try {
                $Server.Query("EXEC master.dbo.sp_dropserver @server=N'$Name', @droplogins='droplogins'")
            } catch {
                # Absent is the state we are asking for, and sp_dropserver has no IF EXISTS form.
                $null = 1
            }
            $Server.LinkedServers.Refresh()
        }

        function Get-TestLinkedServer {
            param(
                $Server,
                [string]$Name
            )
            $Server.LinkedServers.Refresh()
            $Server.LinkedServers[$Name]
        }

        foreach ($name in $fixtureNames) {
            Remove-TestLinkedServer -Server $sourceServer -Name $name
            Remove-TestLinkedServer -Server $destServer -Name $name
        }

        # @srvproduct='SQL Server' reports back as ProviderName SQLNCLI with DataSource equal to the
        # linked server's own name, so this one exercises the plain path and nothing else.
        $sourceServer.Query("EXEC master.dbo.sp_addlinkedserver @server = N'$linkedServerWithLogin', @srvproduct=N'SQL Server';
        EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'$linkedServerWithLogin',@useself=N'False',@locallogin=NULL,@rmtuser=N'testuser1',@rmtpassword='supfool'")

        $sourceServer.Query("EXEC master.dbo.sp_addlinkedserver @server=N'$linkedServerOldClient', @srvproduct=N'', @provider=N'SQLNCLI10', @datasrc=N'$($TestConfig.InstanceCopy2)'")

        $sourceServer.Query("EXEC master.dbo.sp_addlinkedserver @server=N'$linkedServerNoProvider', @srvproduct=N'', @provider=N'Dbatoolsci.NotAProvider', @datasrc=N'nowhere'")

        $sourceServer.LinkedServers.Refresh()

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        foreach ($name in $fixtureNames) {
            Remove-TestLinkedServer -Server $sourceServer -Name $name
            Remove-TestLinkedServer -Server $destServer -Name $name
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When the linked server carries a remote login" {
        It "Copies the linked server and sets its remote password" {
            Remove-TestLinkedServer -Server $destServer -Name $linkedServerWithLogin

            $splatCopyLogin = @{
                Source       = $TestConfig.InstanceCopy1
                Destination  = $TestConfig.InstanceCopy2
                LinkedServer = $linkedServerWithLogin
            }
            $results = Copy-DbaLinkedServer @splatCopyLogin

            # Two rows: the linked server itself, then its one remote login.
            @($results).Count | Should -Be 2
            @($results.Status | Select-Object -Unique) | Should -BeExactly "Successful"
            @($results.Name | Select-Object -Unique) | Should -BeExactly $linkedServerWithLogin
            @($results.Notes | Select-Object -Unique) | Should -BeExactly "SQLNCLI"

            $copied = Get-TestLinkedServer -Server $destServer -Name $linkedServerWithLogin
            $copied | Should -Not -BeNullOrEmpty
            $copied.LinkedServerLogins.RemoteUser | Should -Contain "testuser1"
        }

        It "Reports both rows with the login identity, because the status object is reused" {
            Remove-TestLinkedServer -Server $destServer -Name $linkedServerWithLogin

            $splatCopyReuse = @{
                Source       = $TestConfig.InstanceCopy1
                Destination  = $TestConfig.InstanceCopy2
                LinkedServer = $linkedServerWithLogin
            }
            $results = Copy-DbaLinkedServer @splatCopyReuse

            # One status object is mutated and emitted twice, so the "Linked Server" row is already
            # gone from the first emission by the time the login row sets Type. Emitting a fresh
            # object per row would read "Linked Server" then "testuser1" instead.
            @($results.Type | Select-Object -Unique) | Should -BeExactly "testuser1"
        }

        It "Emits only the linked server row when -ExcludePassword" {
            Remove-TestLinkedServer -Server $destServer -Name $linkedServerWithLogin

            $splatCopyNoPassword = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                LinkedServer    = $linkedServerWithLogin
                ExcludePassword = $true
            }
            $results = Copy-DbaLinkedServer @splatCopyNoPassword

            @($results).Count | Should -Be 1
            $results.Type | Should -BeExactly "Linked Server"
            $results.Status | Should -BeExactly "Successful"
            Get-TestLinkedServer -Server $destServer -Name $linkedServerWithLogin | Should -Not -BeNullOrEmpty
        }
    }

    Context "When -WhatIf is used" {
        It "Emits nothing and leaves the destination untouched" {
            Remove-TestLinkedServer -Server $destServer -Name $linkedServerOldClient

            $splatWhatIf = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                LinkedServer    = $linkedServerOldClient
                ExcludePassword = $true
                WhatIf          = $true
            }
            $results = Copy-DbaLinkedServer @splatWhatIf

            @($results).Count | Should -Be 0
            Get-TestLinkedServer -Server $destServer -Name $linkedServerOldClient | Should -BeNullOrEmpty
        }
    }

    Context "When the linked server already exists on the destination" {
        BeforeEach {
            # Seeded pointing somewhere the source fixture does not, so "skipped" and "dropped and
            # recreated" are told apart by what the destination holds afterwards. A name check alone
            # passes either way.
            #
            # The discriminator is @datasrc and not @provider on purpose: sp_addlinkedserver
            # rewrites SQLOLEDB to SQLNCLI on the way in, so a seed asking for one reads back as the
            # other and the assertion would fail on the seed rather than on the command.
            Remove-TestLinkedServer -Server $destServer -Name $linkedServerOldClient
            $destServer.Query("EXEC master.dbo.sp_addlinkedserver @server=N'$linkedServerOldClient', @srvproduct=N'', @provider=N'SQLOLEDB', @datasrc=N'dbatoolsci_placeholder'")
            $destServer.LinkedServers.Refresh()
        }

        It "Skips it and leaves the existing definition in place" {
            $splatCopySkip = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                LinkedServer    = $linkedServerOldClient
                ExcludePassword = $true
            }
            $results = Copy-DbaLinkedServer @splatCopySkip

            @($results).Count | Should -Be 1
            $results.Status | Should -BeExactly "Skipped"
            $results.Notes | Should -BeExactly "Already exists on destination"
            (Get-TestLinkedServer -Server $destServer -Name $linkedServerOldClient).DataSource | Should -BeExactly "dbatoolsci_placeholder"
        }

        It "Drops and recreates it under -Force" {
            $splatCopyForce = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                LinkedServer    = $linkedServerOldClient
                ExcludePassword = $true
                Force           = $true
            }
            $results = Copy-DbaLinkedServer @splatCopyForce

            $results.Status | Should -BeExactly "Successful"
            $recreated = Get-TestLinkedServer -Server $destServer -Name $linkedServerOldClient
            $recreated.DataSource | Should -BeExactly $TestConfig.InstanceCopy2
            $recreated.ProviderName | Should -BeExactly "SQLNCLI10"
        }
    }

    Context "When the destination does not carry the provider" {
        It "Skips the linked server and creates nothing" {
            Remove-TestLinkedServer -Server $destServer -Name $linkedServerNoProvider

            $splatCopyMissing = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                LinkedServer    = $linkedServerNoProvider
                ExcludePassword = $true
            }
            $results = Copy-DbaLinkedServer @splatCopyMissing

            @($results).Count | Should -Be 1
            $results.Status | Should -BeExactly "Skipped"
            $results.Notes | Should -BeExactly "Missing provider"
            Get-TestLinkedServer -Server $destServer -Name $linkedServerNoProvider | Should -BeNullOrEmpty
        }
    }

    Context "When the source names an older SQL Native Client" {
        It "Keeps the source provider by default" {
            Remove-TestLinkedServer -Server $destServer -Name $linkedServerOldClient

            $splatCopyKeepClient = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                LinkedServer    = $linkedServerOldClient
                ExcludePassword = $true
            }
            $results = Copy-DbaLinkedServer @splatCopyKeepClient

            $results.Status | Should -BeExactly "Successful"
            (Get-TestLinkedServer -Server $destServer -Name $linkedServerOldClient).ProviderName | Should -BeExactly "SQLNCLI10"
        }

        It "Rewrites it to the destination's newest one with -UpgradeSqlClient" {
            Remove-TestLinkedServer -Server $destServer -Name $linkedServerOldClient

            $splatCopyUpgrade = @{
                Source           = $TestConfig.InstanceCopy1
                Destination      = $TestConfig.InstanceCopy2
                LinkedServer     = $linkedServerOldClient
                ExcludePassword  = $true
                UpgradeSqlClient = $true
            }
            $results = Copy-DbaLinkedServer @splatCopyUpgrade

            $results.Status | Should -BeExactly "Successful"
            $upgraded = Get-TestLinkedServer -Server $destServer -Name $linkedServerOldClient
            $upgraded.ProviderName | Should -BeExactly $newestClientProvider
            $upgraded.ProviderName | Should -Not -BeExactly "SQLNCLI10"
        }
    }

    Context "When both name filters are supplied" {
        It "Applies -ExcludeLinkedServer on top of -LinkedServer" {
            Remove-TestLinkedServer -Server $destServer -Name $linkedServerOldClient
            Remove-TestLinkedServer -Server $destServer -Name $linkedServerNoProvider

            $splatCopyBothFilters = @{
                Source              = $TestConfig.InstanceCopy1
                Destination         = $TestConfig.InstanceCopy2
                LinkedServer        = $linkedServerOldClient, $linkedServerNoProvider
                ExcludeLinkedServer = $linkedServerNoProvider
                ExcludePassword     = $true
            }
            $results = Copy-DbaLinkedServer @splatCopyBothFilters

            # The help says -ExcludeLinkedServer is ignored when -LinkedServer is supplied. It is
            # not: both filters run, in that order. The excluded name produces no row at all, which
            # is what separates "filtered out before the loop" from "reached the loop and skipped".
            @($results).Count | Should -Be 1
            $results.Name | Should -BeExactly $linkedServerOldClient
            $results.Notes | Should -Not -BeExactly "Missing provider"
        }
    }

    Context "When more than one destination is supplied" {
        It "Walks every destination in order" {
            Remove-TestLinkedServer -Server $destServer -Name $linkedServerOldClient

            $splatCopyTwoDestinations = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2, $TestConfig.InstanceCopy2
                LinkedServer    = $linkedServerOldClient
                ExcludePassword = $true
            }
            $results = Copy-DbaLinkedServer @splatCopyTwoDestinations

            # The same destination twice: the first pass creates it, the second finds it there. A
            # port that walked the array once would report a single row.
            @($results).Count | Should -Be 2
            $results[0].Status | Should -BeExactly "Successful"
            $results[1].Status | Should -BeExactly "Skipped"
        }
    }
}
