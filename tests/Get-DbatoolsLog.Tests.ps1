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
                # A file that the cleanup of the logging runspace removes between the two commands is skipped, the next
                # round reads the files again.
                $match = Get-ChildItem -Path $logPath -Filter $logFilter -ErrorAction SilentlyContinue | Select-String -Pattern $Marker -SimpleMatch -ErrorAction SilentlyContinue | Select-Object -First 1
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

        It "Writes a message that arrives while the file refuses writers once the file is free again" {
            # A limit far above the size of the file, so that no new file is started while the current one is held.
            Set-DbatoolsConfig -FullName "Logging.MaxMessagefileBytes" -Value 100MB

            $firstMarker = "dbatoolsci_logfree_$(Get-Random)"
            Write-Message -Level Verbose -Message $firstMarker -FunctionName $CommandName
            $firstMatch = Wait-MessageLogLine -Marker $firstMarker
            $firstMatch | Should -Not -BeNullOrEmpty

            # A reader that shares only reading keeps every writer out of the file, like a program that reads the log while
            # the logging runspace wants to write it. Twelve seconds cover two passes of the logging runspace.
            $heldMarker = "dbatoolsci_logheld_$(Get-Random)"
            $holder = [System.IO.File]::Open($firstMatch.Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            try {
                Write-Message -Level Verbose -Message $heldMarker -FunctionName $CommandName
                Start-Sleep -Seconds 12
            } finally {
                $holder.Dispose()
            }

            Wait-MessageLogLine -Marker $heldMarker | Should -Not -BeNullOrEmpty
        }

        It "Keeps writing into one file when the size of a file is not limited" {
            Set-DbatoolsConfig -FullName "Logging.MaxMessagefileBytes" -Value 0

            $fileNames = foreach ($number in 1..2) {
                $marker = "dbatoolsci_lognolimit_$(Get-Random)"
                Write-Message -Level Verbose -Message $marker -FunctionName $CommandName
                $match = Wait-MessageLogLine -Marker $marker
                $match | Should -Not -BeNullOrEmpty
                $match.Filename
            }

            $fileNames | Select-Object -Unique | Should -HaveCount 1
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>