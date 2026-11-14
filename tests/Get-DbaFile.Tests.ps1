#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaFile",
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
                "Path",
                "FileType",
                "Depth",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Returns some files" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $random = Get-Random
            $testDbName = "dbatoolsci_getfile$random"
            $server.Query("CREATE DATABASE $testDbName")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testDbName | Remove-DbaDatabase

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should find the new database file" {
            $results = Get-DbaFile -SqlInstance $TestConfig.InstanceSingle
            ($results.Filename -match "dbatoolsci").Count | Should -BeGreaterThan 0
        }

        It "Should find the new database log file" {
            $logPath = (Get-DbaDefaultPath -SqlInstance $TestConfig.InstanceSingle).Log
            $results = Get-DbaFile -SqlInstance $TestConfig.InstanceSingle -Path $logPath
            ($results.Filename -like "*dbatoolsci*ldf").Count | Should -BeGreaterThan 0
        }

        It "Should find the master database file" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $masterPath = $server.MasterDBPath
            $results = Get-DbaFile -SqlInstance $TestConfig.InstanceSingle -Path $masterPath
            ($results.Filename -match "master.mdf").Count | Should -BeGreaterThan 0
        }
    }

    Context "Logins without sysadmin and paths that need quoting (#10839)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Before SQL Server 2017 there is only xp_dirtree, which lists nothing for a login that is not sysadmin
            $supportsFileSystemDmf = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).VersionMajor -ge 14

            # A new login is only a member of public
            $loginName = "dbatoolsci_getfile_$(Get-Random)"
            $loginPassword = ConvertTo-SecureString -String "dbatools.IO$(Get-Random)" -AsPlainText -Force
            $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $loginName -SecurePassword $loginPassword
            $loginCredential = New-Object System.Management.Automation.PSCredential($loginName, $loginPassword)

            # The instance lists these folders, so they go to the temp folder that the instance can reach.
            # The name of the Unicode folder is built from code points, because Windows PowerShell reads a test
            # file without byte order mark in the ANSI code page.
            $treePath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $quoteFolder = "$treePath\dbatoolsci_O'Brien"
            $unicodeFolder = "$treePath\dbatoolsci_M$([char]0x00FC)ller_$([char]0x65E5)$([char]0x672C)"
            $null = New-Item -Path "$treePath\sub1\sub2", $quoteFolder, $unicodeFolder -ItemType Directory
            $treeFiles = @(
                "$treePath\a.cer",
                "$treePath\f.pvk",
                "$quoteFolder\d.cer",
                "$unicodeFolder\e.cer",
                "$treePath\sub1\sub2\c.cer"
            )
            foreach ($treeFile in $treeFiles) {
                Set-Content -LiteralPath $treeFile -Value "dbatoolsci"
            }

            # A folder created on a share can stay invisible to the instance for some seconds
            $visibleBefore = (Get-Date).AddSeconds(60)
            while (-not (Test-DbaPath -SqlInstance $TestConfig.InstanceSingle -Path "$treePath\sub1\sub2\c.cer") -and (Get-Date) -lt $visibleBefore) {
                Start-Sleep -Seconds 2
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Force, because Get-DbaFile leaves the session of the login in the connection pool
            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $loginName -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $treePath -Recurse -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Finds the files for a login that is not sysadmin" {
            if (-not $supportsFileSystemDmf) {
                Set-ItResult -Skipped -Because "xp_dirtree lists nothing for a login that is not sysadmin before SQL Server 2017"
            }
            # xp_dirtree returned no row for such a login, so nothing was found and nothing was said
            $results = Get-DbaFile -SqlInstance $TestConfig.InstanceSingle -SqlCredential $loginCredential -Path $treePath -FileType cer
            $results.Filename | Should -Be "$treePath\a.cer"
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Lists the levels that -Depth asks for and every level for a depth of 0" {
            $results = Get-DbaFile -SqlInstance $TestConfig.InstanceSingle -Path $treePath
            @($results).Count | Should -Be 5
            $results = Get-DbaFile -SqlInstance $TestConfig.InstanceSingle -Path $treePath -Depth 2
            @($results).Count | Should -Be 8
            $results = Get-DbaFile -SqlInstance $TestConfig.InstanceSingle -Path $treePath -Depth 0 -FileType cer
            $expectedFiles = $treeFiles | Where-Object { $PSItem -like "*.cer" }
            Compare-Object -ReferenceObject $expectedFiles -DifferenceObject @($results.Filename) | Should -BeNullOrEmpty
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Lists folders whose names need quoting" {
            # The path went into the query without quoting and without N, so a quote broke the batch and a character
            # outside the code page of the instance pointed to a folder that does not exist
            $results = Get-DbaFile -SqlInstance $TestConfig.InstanceSingle -Path $quoteFolder, $unicodeFolder -FileType cer
            Compare-Object -ReferenceObject @("$quoteFolder\d.cer", "$unicodeFolder\e.cer") -DifferenceObject @($results.Filename) | Should -BeNullOrEmpty
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Returns full paths below the folder also without -FileType" {
            # Without -FileType every doubled backslash was replaced, so a path on a share lost its leading backslash
            $results = Get-DbaFile -SqlInstance $TestConfig.InstanceSingle -Path $treePath
            @($results).Count | Should -Be 5
            $results.Filename | Where-Object { $PSItem -notlike "$treePath\*" } | Should -BeNullOrEmpty
        }

        It "Warns instead of ending with an exception when the query fails" {
            # Every level of the system drive takes longer than a statement timeout of one second
            $timeoutServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -StatementTimeout 1
            $driveRoot = $timeoutServer.RootDirectory.Substring(0, 3)
            $results = Get-DbaFile -SqlInstance $timeoutServer -Path $driveRoot -Depth 0 -WarningAction SilentlyContinue
            $timeoutServer.ConnectionContext.Disconnect()
            $results | Should -BeNullOrEmpty
            $WarnVar | Should -BeLike "*Failure listing the path(s)*"
        }
    }
}