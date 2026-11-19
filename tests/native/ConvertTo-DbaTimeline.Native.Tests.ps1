#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: azure-sqldb N/A -- Renders supplied history objects as HTML without querying a database; this converter has no SQL connection or Azure-specific execution path.
param(
    $ModuleName = "dbatools",
    $CommandName = "ConvertTo-DbaTimeline",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- this object-to-text conversion has no SupportsShouldProcess or external changes.
# NativeChecklist: multi-instance-failure N/A -- this converter accepts objects and opens no instance connections.
Describe "Native ConvertTo-DbaTimeline" -Tag UnitTests {
    BeforeAll {
        function New-NativeTimelineJob {
            param([string]$Server, [string]$Job = "nightly", [string]$Status = "Succeeded")
            [PSCustomObject]@{
                TypeName = "AgentJobHistory"
                SqlInstance = $Server
                InstanceName = "MSSQLSERVER"
                Job = $Job
                Status = $Status
                StartDate = [datetime]"2024-01-01T00:00:00"
                EndDate = [datetime]"2024-01-01T00:01:00"
            }
        }
    }

    It "accepts DateFormat positionally with positional or named input" {
        $nativeTimelineJob = New-NativeTimelineJob -Server "sql1"
        $nativeTimelinePositional = @(ConvertTo-DbaTimeline $nativeTimelineJob 'MM/dd')
        $nativeTimelineNamedInput = @(ConvertTo-DbaTimeline -InputObject $nativeTimelineJob 'MM/dd')
        $nativeTimelinePositional.Count | Should -Be 3
        $nativeTimelineNamedInput.Count | Should -Be 3
        ($nativeTimelinePositional -join " ") | Should -Match ([regex]::Escape("format: 'MM/dd HH:mm'"))
        ($nativeTimelineNamedInput -join " ") | Should -Match ([regex]::Escape("format: 'MM/dd HH:mm'"))
    }

    It "encodes caller text for script and HTML contexts without deleting name characters" {
        $nativeTimelineServer = "sql</code><img src=x onerror=alert(1)>"
        $nativeTimelineJob = New-NativeTimelineJob -Server $nativeTimelineServer -Job "O'Reilly" -Status "Succeeded';alert(1);//</script>"
        $nativeTimelineHtml = @($nativeTimelineJob | ConvertTo-DbaTimeline)
        $nativeTimelineHtml.Count | Should -Be 3
        $nativeTimelineBody = $nativeTimelineHtml[1] -join " "
        $nativeTimelineBody | Should -Match ([regex]::Escape("O\'Reilly"))
        $nativeTimelineBody | Should -Not -Match ([regex]::Escape("</script>"))
        $nativeTimelineBody | Should -Match ([regex]::Escape("\u003c/script\u003e"))
        $nativeTimelineHtml[2] | Should -Not -Match ([regex]::Escape($nativeTimelineServer))
        $nativeTimelineHtml[2] | Should -Match ([regex]::Escape("sql&lt;/code&gt;&lt;img src=x onerror=alert(1)&gt;"))
    }

    It "keeps both instance labels for a direct array containing multiple servers" {
        $nativeTimelineFirst = New-NativeTimelineJob -Server "sql1"
        $nativeTimelineSecond = New-NativeTimelineJob -Server "sql2"
        $nativeTimelineHtml = @(ConvertTo-DbaTimeline -InputObject @($nativeTimelineFirst, $nativeTimelineSecond))
        ($nativeTimelineHtml[1] -join " ") | Should -Match ([regex]::Escape("[sql1] nightly"))
        ($nativeTimelineHtml[1] -join " ") | Should -Match ([regex]::Escape("[sql2] nightly"))
        $nativeTimelineHtml[2] | Should -Match ([regex]::Escape("sql1, sql2"))
    }

    It "uses Gregorian date components regardless of the host calendar" {
        $nativeTimelineJob = New-NativeTimelineJob -Server "sql1"
        $nativeTimelineCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("th-TH")
            $nativeTimelineHtml = @($nativeTimelineJob | ConvertTo-DbaTimeline)
            ($nativeTimelineHtml[1] -join " ") | Should -Match ([regex]::Escape("new Date(2024, 0, 01, 00, 00, 00)"))
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("ar-SA")
            $nativeTimelineJob.StartDate = New-Object System.DateTime -ArgumentList 1753, 1, 1
            $nativeTimelineJob.EndDate = $nativeTimelineJob.StartDate.AddMinutes(1)
            $nativeTimelineHtml = @($nativeTimelineJob | ConvertTo-DbaTimeline)
            ($nativeTimelineHtml[1] -join " ") | Should -Match ([regex]::Escape("new Date(1753, 0, 01, 00, 00, 00)"))
        } finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $nativeTimelineCulture
        }
    }

    It "preserves multiple pipeline records and explicit false switches" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:switch-false" {
        $nativeTimelineFirst = New-NativeTimelineJob -Server "sql1" -Job "first"
        $nativeTimelineSecond = New-NativeTimelineJob -Server "sql1" -Job "second"
        $nativeTimelineHtml = @(@($nativeTimelineFirst, $nativeTimelineSecond) | ConvertTo-DbaTimeline -ExcludeRowLabel:$false -EnableException:$false)
        $nativeTimelineHtml.Count | Should -Be 3
        @($nativeTimelineHtml[1]).Count | Should -Be 2
        ($nativeTimelineHtml[1] -join " ") | Should -Match "first"
        ($nativeTimelineHtml[1] -join " ") | Should -Match "second"
        $nativeTimelineHtml[2] | Should -Match "showRowLabels: true"
    }

    It "warns and emits no document for unsupported input with exceptions disabled" -Tag "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativeTimelineResult = @([PSCustomObject]@{ Unknown = 1 } | ConvertTo-DbaTimeline -EnableException:$false -WarningAction SilentlyContinue -WarningVariable nativeTimelineWarning)
        $nativeTimelineResult.Count | Should -Be 0
        ($nativeTimelineWarning -join " ") | Should -BeLike "*Unsupported input data.*"
    }

    It "throws for unsupported input when exceptions are enabled" -Tag "NativeChecklist:enable-exception" {
        { [PSCustomObject]@{ Unknown = 1 } | ConvertTo-DbaTimeline -EnableException } | Should -Throw "*Unsupported input data.*"
    }
}
