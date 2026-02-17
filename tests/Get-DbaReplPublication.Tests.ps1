#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaReplPublication",
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
                "Name",
                "Type",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Code Validation" {
            BeforeAll {
                Mock Connect-ReplicationDB -MockWith {
                    [object] @{
                        Name              = "TestDB"
                        TransPublications = @{
                            Name         = "TestDB_pub"
                            Type         = "Transactional"
                            DatabaseName = "TestDB"
                        }
                        MergePublications = @{ }
                    }
                }

                Mock Connect-DbaInstance -MockWith {
                    [object] @{
                        Name               = "MockServerName"
                        ServiceName        = "MSSQLSERVER"
                        DomainInstanceName = "MockServerName"
                        ComputerName       = "MockComputerName"
                        Databases          = @{
                            Name               = "TestDB"
                            #state
                            #status
                            ID                 = 5
                            ReplicationOptions = "Published"
                            IsAccessible       = $true
                            IsSystemObject     = $false
                        }
                        ConnectionContext  = @{
                            SqlConnectionObject = "FakeConnectionContext"
                        }
                    }
                }
            }

            It "Honors the SQLInstance parameter" {
                $Results = Get-DbaReplPublication -SqlInstance MockServerName
                $Results.SqlInstance.Name | Should -Be "MockServerName"
            }

            It "Honors the Database parameter" {
                $Results = Get-DbaReplPublication -SqlInstance MockServerName -Database TestDB
                $Results.DatabaseName | Should -Be "TestDB"
            }

            It "Honors the Type parameter" {
                Mock Connect-ReplicationDB -MockWith {
                    [object] @{
                        Name              = "TestDB"
                        TransPublications = @{
                            Name = "TestDB_pub"
                            Type = "Snapshot"
                        }
                        MergePublications = @{ }
                    }
                }

                $Results = Get-DbaReplPublication -SqlInstance MockServerName -Database TestDB -Type Snapshot
                $Results.Type | Should -Be "Snapshot"
            }

            It "Stops if validate set for Type is not met" {
                { Get-DbaReplPublication -SqlInstance MockServerName -Type NotAPubType } | Should -Throw
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Check if replication is configured - skip all tests if not
        $replServer = Get-DbaReplServer -SqlInstance $TestConfig.InstanceSingle
        $global:skipRepl = -not $replServer.IsPublisher

        if (-not $global:skipRepl) {
            # Create test database and table for replication
            $dbName = "dbatoolsci_replpub_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbName
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Query "CREATE TABLE ReplicateMe (id int identity(1,1) PRIMARY KEY, col1 varchar(10))"

            # Create transactional publication and add an article
            $pubName = "dbatoolsci_TestPub_$(Get-Random)"
            $splatPub = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Type        = "Transactional"
                Name        = $pubName
            }
            $null = New-DbaReplPublication @splatPub
            $null = Add-DbaReplArticle -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Publication $pubName -Name "ReplicateMe"
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if (-not $global:skipRepl) {
            # Clean up publication then database
            Remove-DbaReplPublication -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Name $pubName -Confirm:$false -ErrorAction SilentlyContinue
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName -Confirm:$false -ErrorAction SilentlyContinue
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When getting publications" -Skip:$global:skipRepl {
        It "Should return publications" {
            $splatGetPub = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Name        = $pubName
            }
            $result = Get-DbaReplPublication @splatGetPub -OutVariable "global:dbatoolsciOutput"
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Contain $pubName
            $result.DatabaseName | Should -Contain $dbName
        }
    }

    Context "Output validation" -Skip:$global:skipRepl {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Replication.TransPublication]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SQLInstance",
                "DatabaseName",
                "Name",
                "Type",
                "Articles",
                "Subscriptions"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Replication\.Publication"
        }
    }
}