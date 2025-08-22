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
        $global:tPassword = ConvertTo-SecureString "ThisIsThePassword1" -AsPlainText -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database enctest -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "commands work as expected" {
        It "Should create new key in master called test1" {
            if (!(Get-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database master )) {
                New-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database master -SecurePassword $global:tPassword -Confirm:$false
            }
            $global:keyname1 = "test1"
            $global:key1 = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $global:keyname1
            $global:results1 = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $global:keyname1 -Database master -WarningVariable global:warnvar1
            $global:warnvar1 | Should -BeNullOrEmpty
            $global:results1.database | Should -Be "master"
            $global:results1.name | Should -Be $global:keyname1
            $global:results1.KeyLength | Should -Be "2048"
        }
    }

    Context "Handles pre-existing key" {
        AfterAll {
            Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $global:keyname2 -Database master -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Should Warn that they key test1 already exists" {
            $global:keyname2 = "test1"
            $global:key2 = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $global:keyname2 -Database master -WarningVariable global:warnvar2 3> $null
            $global:warnvar2 | Should -BeLike "*already exists in master on*"
        }
    }

    Context "Handles Algorithm changes" {
        AfterAll {
            Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $global:keyname3 -Database master -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Should Create new key in master called test2" {
            $global:keyname3 = "test2"
            $global:algorithm3 = "Rsa4096"
            $global:key3 = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $global:keyname3 -Algorithm $global:algorithm3 -WarningVariable global:warnvar3
            $global:results3 = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $global:keyname3 -Database master
            $global:warnvar3 | Should -BeNullOrEmpty
            $global:results3.database | Should -Be "master"
            $global:results3.name | Should -Be $global:keyname3
            $global:results3.KeyLength | Should -Be 4096
        }
    }

    Context "Non master database" {
        AfterAll {
            Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $global:keyname4 -Database $global:database4 -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Should Create new key in enctest called test4" {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $global:keyname4 = "test4"
            $global:algorithm4 = "Rsa4096"
            $global:dbuser4 = "keyowner"
            $global:database4 = "enctest"

            New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $global:database4
            New-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database $global:database4 -SecurePassword $global:tPassword -Confirm:$false
            New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $global:database4 -UserName $global:dbuser4

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $global:key4 = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Database $global:database4 -Name $global:keyname4 -Owner keyowner -Algorithm $global:algorithm4 -WarningVariable global:warnvar4
            $global:results4 = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $global:keyname4 -Database $global:database4
            $global:warnvar4 | Should -BeNullOrEmpty
            $global:results4.database | Should -Be $global:database4
            $global:results4.name | Should -Be $global:keyname4
            $global:results4.KeyLength | Should -Be 4096
            $global:results4.Owner | Should -Be $global:dbuser4
        }
    }

    Context "Sets owner correctly" {
        AfterAll {
            Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $global:keyname5 -Database $global:database5 -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Should Create new key in enctest called test3" {
            $global:keyname5 = "test3"
            $global:algorithm5 = "Rsa4096"
            $global:dbuser5 = "keyowner"
            $global:database5 = "enctest"
            $global:key5 = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $global:keyname5 -Owner keyowner -Database $global:database5 -Algorithm $global:algorithm5 -WarningVariable global:warnvar5
            $global:results5 = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $global:keyname5 -Database $global:database5
            $global:warnvar5 | Should -BeNullOrEmpty
            $global:results5.database | Should -Be $global:database5
            $global:results5.name | Should -Be $global:keyname5
            $global:results5.KeyLength | Should -Be 4096
            $global:results5.Owner | Should -Be $global:dbuser5
        }
    }

    Context "Create new key loaded from a keyfile" {
        AfterAll {
            Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $global:keyname6 -Database $global:database6 -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Should Create new key in enctest called filekey" {
            $global:skip6 = $false
            $global:keyname6 = "filekey"
            $global:dbuser6 = "keyowner"
            $global:database6 = "enctest"
            $global:path6 = "$($($TestConfig.appveyorlabrepo))\keytests\keypair.snk"

            if (Test-Path -Path $global:path6) {
                $global:key6 = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Database $global:database6 -Name $global:keyname6 -Owner keyowner -WarningVariable global:warnvar6 -KeySourceType File -KeySource $global:path6
                $global:results6 = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $global:keyname6 -Database $global:database6
                $global:warnvar6 | Should -BeNullOrEmpty
                $global:results6.database | Should -Be $global:database6
                $global:results6.name | Should -Be $global:keyname6
                $global:results6.Owner | Should -Be $global:dbuser6
            } else {
                Write-Warning -Message "No keypair found in path [$($global:path6)], skipping tests."
                Set-ItResult -Skipped -Because "No keypair found in path [$($global:path6)]"
            }
        }
    }

    Context "Failed key creation from a missing keyfile" {
        AfterAll {
            Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $global:keyname7 -Database $global:database7 -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Should not Create new key in enctest called filekeybad" {
            $global:keyname7 = "filekeybad"
            $global:dbuser7 = "keyowner"
            $global:database7 = "enctest"
            $global:path7 = "$($($TestConfig.appveyorlabrepo))\keytests\keypair.bad"
            $global:key7 = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Database $global:database7 -Name $global:keyname7 -Owner keyowner -WarningVariable global:warnvar7 -KeySourceType File -KeySource $global:path7 3> $null
            $global:results7 = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $global:keyname7 -Database $global:database7
            $global:warnvar7 | Should -Not -BeNullOrEmpty
            $global:results7 | Should -BeNullOrEmpty
        }
    }
}