param($ModuleName = 'dbatools')

Describe "Import-DbaBinaryFile" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $db = Get-DbaDatabase -SqlInstance $global:instance2 -Database tempdb
        $null = $db.Query("CREATE TABLE [dbo].[BunchOFiles]([FileName123] [nvarchar](50) NULL, [TheFile123] [image] NULL)")
    }

    AfterAll {
        try {
            $null = $db.Query("DROP TABLE dbo.BunchOFiles")
        } catch {
            $null = 1
        }
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Import-DbaBinaryFile
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have Table as a parameter" {
            $CommandUnderTest | Should -HaveParameter Table
        }
        It "Should have Schema as a parameter" {
            $CommandUnderTest | Should -HaveParameter Schema
        }
        It "Should have Statement as a parameter" {
            $CommandUnderTest | Should -HaveParameter Statement
        }
        It "Should have FileNameColumn as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileNameColumn
        }
        It "Should have BinaryColumn as a parameter" {
            $CommandUnderTest | Should -HaveParameter BinaryColumn
        }
        It "Should have NoFileNameColumn as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoFileNameColumn
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have FilePath as a parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        It "imports files into table data" {
            $results = Import-DbaBinaryFile -SqlInstance $global:instance2 -Database tempdb -Table BunchOFiles -FilePath $env:appveyorlabrepo\azure\adalsql.msi -WarningAction Continue -ErrorAction Stop -EnableException
            $results.Database | Should -Be "tempdb"
            $results.FilePath | Should -Match "adalsql.msi"
        }

        It "imports files into table data from piped" {
            $results = Get-ChildItem -Path $env:appveyorlabrepo\certificates | Import-DbaBinaryFile -SqlInstance $global:instance2 -Database tempdb -Table BunchOFiles -WarningAction Continue -ErrorAction Stop -EnableException
            $results.Database | Should -Be @("tempdb", "tempdb")
            Split-Path -Path $results.FilePath -Leaf | Should -Be @("localhost.crt", "localhost.pfx")
        }

        It "piping from Get-DbaBinaryFileTable works" {
            $results = Get-DbaBinaryFileTable -SqlInstance $global:instance2 -Database tempdb -Table BunchOFiles | Import-DbaBinaryFile -WarningAction Continue -ErrorAction Stop -EnableException -Path $env:appveyorlabrepo\certificates
            $results.Database | Should -Be @("tempdb", "tempdb")
            Split-Path -Path $results.FilePath -Leaf | Should -Be @("localhost.crt", "localhost.pfx")
        }
    }
}
