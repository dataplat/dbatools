#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbatoolsLog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "FunctionName",
                "ModuleName",
                "Target",
                "Tag",
                "Last",
                "Skip",
                "Runspace",
                "Level",
                "Raw",
                "Errors",
                "LastError"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # The logging runspace writes the messages of this process to these files every five seconds.
        $logPath = [Dataplat.Dbatools.Message.LogHost]::LoggingPath
        $logFilter = "dbatools_$($PID)_message_*.log"

        function Wait-MessageLogLine {
            param (
                [string]$Marker
            )
            $deadline = (Get-Date).AddSeconds(30)
            while ((Get-Date) -lt $deadline) {
                $match = Get-ChildItem -Path $logPath -Filter $logFilter -ErrorAction SilentlyContinue | Select-String -Pattern $Marker -SimpleMatch | Select-Object -First 1
                if ($match) {
                    return $match
                }
                Start-Sleep -Milliseconds 500
            }
        }

        $originalMaxMessagefileBytes = Get-DbatoolsConfigValue -FullName "Logging.MaxMessagefileBytes"
    }

    AfterAll {
        Set-DbatoolsConfig -FullName "Logging.MaxMessagefileBytes" -Value $originalMaxMessagefileBytes
    }

    Context "Writing the message log file" {
        It "Writes the tags of a message into the Tags column" {
            $marker = "dbatoolsci_logtags_$(Get-Random)"
            Write-Message -Level Verbose -Message $marker -Tag "dbatoolsci_tag1", "dbatoolsci_tag2" -FunctionName $CommandName

            $match = Wait-MessageLogLine -Marker $marker
            $match | Should -Not -BeNullOrEmpty

            # The file has no header, so we take the column names from the entry in memory.
            $entry = Get-DbatoolsLog -Raw | Where-Object Message -eq $marker
            $fileEntry = $match.Line | ConvertFrom-Csv -Header $entry.PSObject.Properties.Name
            $fileEntry.Tags | Should -Be "dbatoolsci_tag1, dbatoolsci_tag2"
            $fileEntry.FunctionName | Should -Be $CommandName
        }

        It "Starts a new file every time the current file is full" {
            # With a limit of one byte every file is full after one line, so every pass of the logging runspace has to start a new file.
            Set-DbatoolsConfig -FullName "Logging.MaxMessagefileBytes" -Value 1

            $fileNames = foreach ($number in 1..3) {
                $marker = "dbatoolsci_logrotate_$(Get-Random)"
                Write-Message -Level Verbose -Message $marker -FunctionName $CommandName
                $match = Wait-MessageLogLine -Marker $marker
                $match | Should -Not -BeNullOrEmpty
                $match.Filename
            }

            $fileNames | Select-Object -Unique | Should -HaveCount 3
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>