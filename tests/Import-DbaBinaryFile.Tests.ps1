param($ModuleName = 'dbatools')

Describe "Import-DbaBinaryFile" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $db = Get-DbaDatabase -SqlInstance $script:instance2 -Database tempdb
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
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String
        }
        It "Should have Table as a parameter" {
            $CommandUnderTest | Should -HaveParameter Table -Type String
        }
        It "Should have Schema as a parameter" {
            $CommandUnderTest | Should -HaveParameter Schema -Type String
        }
        It "Should have Statement as a parameter" {
            $CommandUnderTest | Should -HaveParameter Statement -Type String
        }
        It "Should have FileNameColumn as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileNameColumn -Type String
        }
        It "Should have BinaryColumn as a parameter" {
            $CommandUnderTest | Should -HaveParameter BinaryColumn -Type String
        }
        It "Should have NoFileNameColumn as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoFileNameColumn -Type Switch
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Table[]
        }
        It "Should have FilePath as a parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath -Type FileInfo[]
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type FileInfo[]
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command usage" {
        It "imports files into table data" {
            $results = Import-DbaBinaryFile -SqlInstance $script:instance2 -Database tempdb -Table BunchOFiles -FilePath $script:appveyorlabrepo\azure\adalsql.msi -WarningAction Continue -ErrorAction Stop -EnableException
            $results.Database | Should -Be "tempdb"
            $results.FilePath | Should -Match "adalsql.msi"
        }

        It "imports files into table data from piped" {
            $results = Get-ChildItem -Path $script:appveyorlabrepo\certificates | Import-DbaBinaryFile -SqlInstance $script:instance2 -Database tempdb -Table BunchOFiles -WarningAction Continue -ErrorAction Stop -EnableException
            $results.Database | Should -Be @("tempdb", "tempdb")
            Split-Path -Path $results.FilePath -Leaf | Should -Be @("localhost.crt", "localhost.pfx")
        }

        It "piping from Get-DbaBinaryFileTable works" {
            $results = Get-DbaBinaryFileTable -SqlInstance $script:instance2 -Database tempdb -Table BunchOFiles | Import-DbaBinaryFile -WarningAction Continue -ErrorAction Stop -EnableException -Path $script:appveyorlabrepo\certificates
            $results.Database | Should -Be @("tempdb", "tempdb")
            Split-Path -Path $results.FilePath -Leaf | Should -Be @("localhost.crt", "localhost.pfx")
        }
    }
}
