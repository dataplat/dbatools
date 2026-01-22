#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaAgListener",
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
                "AvailabilityGroup",
                "Name",
                "IPAddress",
                "SubnetIP",
                "SubnetMask",
                "Port",
                "Dhcp",
                "Passthru",
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

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # To add a listener to an availablity group, we need an availability group, an ip address and a port.
        # TODO: Add some negative tests.

        # Set variables. They are available in all the It blocks.
        $agName = "addagdb_group"
        $listenerName = "listener"
        $listenerIp = "127.0.20.1"
        $listenerPort = 14330

        # Create the objects.
        $splatAg = @{
            Primary      = $TestConfig.InstanceHadr
            Name         = $agName
            ClusterType  = "None"
            FailoverMode = "Manual"
            Certificate  = "dbatoolsci_AGCert"
        }
        $ag = New-DbaAvailabilityGroup @splatAg

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agName
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceHadr -Type DatabaseMirroring | Remove-DbaEndpoint

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When creating a listener" {
        BeforeAll {
            $splatListener = @{
                Name      = $listenerName
                IPAddress = $listenerIp
                Port      = $listenerPort
            }
            $results = $ag | Add-DbaAgListener @splatListener
        }

        It "Does not warn" {
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Returns results with proper data" {
            $results.PortNumber | Should -Be $listenerPort
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $splatListener = @{
                SqlInstance = $TestConfig.InstanceHadr
                AvailabilityGroup = $agName
                Name        = "listener2"
                IPAddress   = "127.0.20.2"
                Port        = 14331
                EnableException = $true
            }
            $result = Add-DbaAgListener @splatListener
        }

        AfterAll {
            $null = Remove-DbaAgListener -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agName -Listener "listener2" -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'AvailabilityGroup',
                'Name',
                'PortNumber',
                'ClusterIPConfiguration'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has ComputerName property populated" {
            $result.ComputerName | Should -Not -BeNullOrEmpty
        }

        It "Has SqlInstance property populated" {
            $result.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "Has Name matching the listener name" {
            $result.Name | Should -Be "listener2"
        }

        It "Has PortNumber matching the specified port" {
            $result.PortNumber | Should -Be 14331
        }
    }

    Context "Output with -Passthru" {
        It "Returns listener object before creation when -Passthru specified" {
            $splatListener = @{
                SqlInstance = $TestConfig.InstanceHadr
                AvailabilityGroup = $agName
                Name        = "passthruListener"
                IPAddress   = "127.0.20.3"
                Port        = 14332
                Passthru    = $true
                EnableException = $true
            }
            $result = Add-DbaAgListener @splatListener
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener]
            $result.PSObject.Properties.Name | Should -Contain 'Name'
            $result.PSObject.Properties.Name | Should -Contain 'PortNumber'
        }
    }
}