#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-InvalidFileNameChars",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    BeforeAll {
        # Get the actual invalid characters for validation
        $invalidChars = [IO.Path]::GetInvalidFileNameChars()
    }

    Context "Basic filename sanitization" {
        It "Should remove invalid characters from a simple filename" {
            $result = Remove-InvalidFileNameChars -Name "test:file.txt"
            $result | Should -Be "testfile.txt" -Because "colons are invalid in filenames and should be removed"
        }

        It "Should handle multiple invalid characters" {
            $result = Remove-InvalidFileNameChars -Name "test<>:|file.txt"
            $result | Should -Not -Match "[<>:|]" -Because "all invalid filename characters should be removed"
        }

        It "Should preserve valid characters" {
            $result = Remove-InvalidFileNameChars -Name "valid_file-name123.txt"
            $result | Should -Be "valid_file-name123.txt" -Because "valid filename characters should be preserved"
        }
    }

    Context "SQL Server instance name handling" {
        It "Should sanitize named pipe connection strings" {
            $result = Remove-InvalidFileNameChars -Name "NP:.$SQLSERVER"
            $result | Should -Not -Match ":" -Because "colons from named pipe syntax should be removed"
        }

        It "Should handle instance names with backslashes" {
            $result = Remove-InvalidFileNameChars -Name "SERVER\INSTANCE"
            $result | Should -Not -Match "\\" -Because "backslashes are invalid in filenames"
        }

        It "Should handle TCP connections with ports" {
            $result = Remove-InvalidFileNameChars -Name "tcp:server.domain.com,1433"
            $result | Should -Not -Match ":" -Because "protocol prefixes with colons should be sanitized"
        }

        It "Should handle IPv6 addresses with brackets" {
            $result = Remove-InvalidFileNameChars -Name "[2001:0db8:85a3::8a2e:0370:7334]"
            $invalidChars | ForEach-Object {
                if ($PSItem -eq "[" -or $PSItem -eq "]") {
                    $result | Should -Not -Match [regex]::Escape([string]$PSItem) -Because "brackets are invalid in filenames"
                }
            }
        }
    }

    Context "Edge cases and special scenarios" {
        It "Should handle empty strings" {
            $result = Remove-InvalidFileNameChars -Name ""
            $result | Should -Be "" -Because "empty strings should return empty strings"
        }

        It "Should handle strings with only invalid characters" {
            $result = Remove-InvalidFileNameChars -Name "<>:|"
            $result.Length | Should -BeLessThan 4 -Because "all invalid characters should be removed"
        }

        It "Should handle Unicode characters mixed with invalid characters" {
            $result = Remove-InvalidFileNameChars -Name "tëst:fîlé.txt"
            $result | Should -Not -Match ":" -Because "invalid characters should be removed while preserving Unicode"
            $result | Should -Match "[ëî]" -Because "valid Unicode characters should be preserved"
        }

        It "Should handle very long filenames with invalid characters" {
            $longName = "a" * 200 + ":" + "b" * 100
            $result = Remove-InvalidFileNameChars -Name $longName
            $result | Should -Not -Match ":" -Because "invalid characters should be removed from long filenames"
            $result.Length | Should -Be 300 -Because "only the invalid character should be removed"
        }
    }

    Context "Performance optimization validation" {
        It "Should cache invalid characters pattern for performance" {
            # First call initializes the cache
            $null = Remove-InvalidFileNameChars -Name "test:file.txt"

            # Verify cache variables are set
            $script:InvalidFileNameChars | Should -Not -BeNullOrEmpty -Because "invalid characters should be cached at script scope"
            $script:InvalidFileNameCharsPattern | Should -Not -BeNullOrEmpty -Because "regex pattern should be cached at script scope"
        }

        It "Should produce consistent results across multiple calls" {
            $testName = "test<>:|file?.txt"
            $result1 = Remove-InvalidFileNameChars -Name $testName
            $result2 = Remove-InvalidFileNameChars -Name $testName
            $result3 = Remove-InvalidFileNameChars -Name $testName

            $result1 | Should -Be $result2 -Because "cached pattern should produce consistent results"
            $result2 | Should -Be $result3 -Because "cached pattern should produce consistent results"
        }
    }

    Context "Pipeline input support" {
        It "Should accept pipeline input by value" {
            $result = "test:file.txt" | Remove-InvalidFileNameChars
            $result | Should -Be "testfile.txt" -Because "function should accept pipeline input"
        }

        It "Should handle multiple pipeline inputs" {
            $names = @("test:1.txt", "file|2.txt", "doc<3>.txt")
            $results = $names | Remove-InvalidFileNameChars

            $results | Should -HaveCount 3 -Because "all pipeline inputs should be processed"
            $results | ForEach-Object {
                $PSItem | Should -Not -Match "[:|<>]" -Because "all invalid characters should be removed from pipeline inputs"
            }
        }
    }

    Context "Validation of all platform invalid characters" {
        It "Should remove all characters returned by GetInvalidFileNameChars" {
            $testString = -join $invalidChars
            $result = Remove-InvalidFileNameChars -Name "valid${testString}filename.txt"

            foreach ($char in $invalidChars) {
                $result | Should -Not -Match [regex]::Escape([string]$char) -Because "character '$char' should be removed as it is invalid for filenames"
            }
        }
    }
}
