#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbAsymmetricKey",
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
                "Name",
                "Database",
                "SecurePassword",
                "Owner",
                "KeySource",
                "KeySourceType",
                "InputObject",
                "Algorithm",
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

        # Set up master key password for testing
        $tPassword = ConvertTo-SecureString "ThisIsThePassword1" -AsPlainText -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database enctest -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "commands work as expected" {
        It "Should create new key in master called test1" {
            $keyname1 = "test1"
            $key1 = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname1
            $results1 = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname1 -Database master -WarningVariable warnvar1
            $warnvar1 | Should -BeNullOrEmpty
            $results1.database | Should -Be "master"
            $results1.name | Should -Be $keyname1
            $results1.KeyLength | Should -Be "2048"
        }
    }

    Context "Handles pre-existing key" {
        AfterAll {
            Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname2 -Database master -ErrorAction SilentlyContinue
        }

        It "Should Warn that they key test1 already exists" {
            $keyname2 = "test1"
            $key2 = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname2 -Database master -WarningVariable warnvar2 3> $null
            $warnvar2 | Should -BeLike "*already exists in master on*"
        }
    }

    Context "Handles Algorithm changes" {
        AfterAll {
            Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname3 -Database master -ErrorAction SilentlyContinue
        }

        It "Should Create new key in master called test2" {
            $keyname3 = "test2"
            $algorithm3 = "Rsa4096"
            $key3 = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname3 -Algorithm $algorithm3 -WarningVariable warnvar3
            $results3 = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname3 -Database master
            $warnvar3 | Should -BeNullOrEmpty
            $results3.database | Should -Be "master"
            $results3.name | Should -Be $keyname3
            $results3.KeyLength | Should -Be 4096
        }
    }

    Context "Non master database" {
        AfterAll {
            Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname4 -Database $database4 -ErrorAction SilentlyContinue
        }

        It "Should Create new key in enctest called test4" {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $keyname4 = "test4"
            $algorithm4 = "Rsa4096"
            $dbuser4 = "keyowner"
            $database4 = "enctest"

            New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $database4
            New-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database $database4 -SecurePassword $tPassword
            New-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $database4 -UserName $dbuser4

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $key4 = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database $database4 -Name $keyname4 -Owner keyowner -Algorithm $algorithm4 -WarningVariable warnvar4
            $results4 = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname4 -Database $database4
            $warnvar4 | Should -BeNullOrEmpty
            $results4.database | Should -Be $database4
            $results4.name | Should -Be $keyname4
            $results4.KeyLength | Should -Be 4096
            $results4.Owner | Should -Be $dbuser4
        }
    }

    Context "Sets owner correctly" {
        AfterAll {
            Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname5 -Database $database5 -ErrorAction SilentlyContinue
        }

        It "Should Create new key in enctest called test3" {
            $keyname5 = "test3"
            $algorithm5 = "Rsa4096"
            $dbuser5 = "keyowner"
            $database5 = "enctest"
            $key5 = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname5 -Owner keyowner -Database $database5 -Algorithm $algorithm5 -WarningVariable warnvar5
            $results5 = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname5 -Database $database5
            $warnvar5 | Should -BeNullOrEmpty
            $results5.database | Should -Be $database5
            $results5.name | Should -Be $keyname5
            $results5.KeyLength | Should -Be 4096
            $results5.Owner | Should -Be $dbuser5
        }
    }

    Context "Create new key loaded from a keyfile" {
        AfterAll {
            Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname6 -Database $database6 -ErrorAction SilentlyContinue
        }

        It "Should Create new key in enctest called filekey" {
            $keyname6 = "filekey"
            $dbuser6 = "keyowner"
            $database6 = "enctest"
            $path6 = "$($($TestConfig.appveyorlabrepo))\keytests\keypair.snk"

            if (Test-Path -Path $path6) {
                $key6 = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database $database6 -Name $keyname6 -Owner keyowner -WarningVariable warnvar6 -KeySourceType File -KeySource $path6
                $results6 = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname6 -Database $database6
                $warnvar6 | Should -BeNullOrEmpty
                $results6.database | Should -Be $database6
                $results6.name | Should -Be $keyname6
                $results6.Owner | Should -Be $dbuser6
            } else {
                Write-Warning -Message "No keypair found in path [$($path6)], skipping tests."
                Set-ItResult -Skipped -Because "No keypair found in path [$($path6)]"
            }
        }
    }

    Context "Failed key creation from a missing keyfile" {
        AfterAll {
            Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname7 -Database $database7 -ErrorAction SilentlyContinue
        }

        It "Should not Create new key in enctest called filekeybad" {
            $keyname7 = "filekeybad"
            $dbuser7 = "keyowner"
            $database7 = "enctest"
            $path7 = "$($($TestConfig.appveyorlabrepo))\keytests\keypair.bad"
            $key7 = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Database $database7 -Name $keyname7 -Owner keyowner -WarningVariable warnvar7 -KeySourceType File -KeySource $path7 3> $null
            $results7 = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $keyname7 -Database $database7
            $warnvar7 | Should -Not -BeNullOrEmpty
            $results7 | Should -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputKeyName = "dbatoolsci_outputkey_$(Get-Random)"
            $result = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $outputKeyName -Database master
        }

        AfterAll {
            Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.InstanceSingle -Name $outputKeyName -Database master -ErrorAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result.psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.AsymmetricKey"
        }

        It "Has the expected default display properties" {
            $result | Should -Not -BeNullOrEmpty
            $defaultProps = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Database", "Name", "Owner", "KeyEncryptionAlgorithm", "KeyLength", "PrivateKeyEncryptionType", "Thumbprint")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}