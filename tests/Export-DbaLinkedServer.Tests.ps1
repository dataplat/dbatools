#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaLinkedServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "LinkedServer",
                "SqlCredential",
                "Credential",
                "Path",
                "FilePath",
                "ExcludePassword",
                "Append",
                "Passthru",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Create a test linked server to export
            $splatLinkedServer = @{
                SqlInstance     = $TestConfig.instance1
                LinkedServer    = "dbatoolsExportTest"
                ServerProduct   = "SQL Server"
                EnableException = $true
            }
            $null = New-DbaLinkedServer @splatLinkedServer

            # Test output with -Passthru
            $resultPassthru = Export-DbaLinkedServer -SqlInstance $TestConfig.instance1 -LinkedServer "dbatoolsExportTest" -Passthru -EnableException
        }

        AfterAll {
            # Clean up test linked server
            Remove-DbaLinkedServer -SqlInstance $TestConfig.instance1 -LinkedServer "dbatoolsExportTest" -Confirm:$false -EnableException
        }

        It "Returns System.String when -Passthru is specified" {
            $resultPassthru | Should -BeOfType [System.String]
        }

        It "Returns T-SQL script content with -Passthru" {
            $resultPassthru | Should -Match "EXEC master.dbo.sp_addlinkedserver"
            $resultPassthru | Should -Match "dbatoolsExportTest"
        }
    }

    Context "Output Validation with File Output" {
        BeforeAll {
            # Create a test linked server to export
            $splatLinkedServer = @{
                SqlInstance     = $TestConfig.instance1
                LinkedServer    = "dbatoolsFileTest"
                ServerProduct   = "SQL Server"
                EnableException = $true
            }
            $null = New-DbaLinkedServer @splatLinkedServer

            # Test output with -FilePath
            $tempFile = [System.IO.Path]::GetTempFileName()
            $resultFile = Export-DbaLinkedServer -SqlInstance $TestConfig.instance1 -LinkedServer "dbatoolsFileTest" -FilePath $tempFile -EnableException
        }

        AfterAll {
            # Clean up test linked server
            Remove-DbaLinkedServer -SqlInstance $TestConfig.instance1 -LinkedServer "dbatoolsFileTest" -Confirm:$false -EnableException
            # Clean up temp file
            if (Test-Path $tempFile) {
                Remove-Item $tempFile -Force
            }
        }

        It "Returns System.IO.FileInfo when -FilePath is specified" {
            $resultFile | Should -BeOfType [System.IO.FileInfo]
        }

        It "Has the expected FileInfo properties" {
            $expectedProps = @(
                'FullName',
                'Name',
                'Directory',
                'Length',
                'LastWriteTime'
            )
            $actualProps = $resultFile.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available"
            }
        }

        It "Creates a file with T-SQL content" {
            $resultFile.FullName | Should -Exist
            $content = Get-Content -Path $resultFile.FullName -Raw
            $content | Should -Match "EXEC master.dbo.sp_addlinkedserver"
            $content | Should -Match "dbatoolsFileTest"
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>