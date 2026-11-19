#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Convert-DbaTimelineStatusColor",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Private timeline color behavior" {
    BeforeAll {
        $colorModule = Get-Module dbatools | Where-Object ModuleType -eq Script
    }

    It "preserves mandatory scalar binding without pipeline or exception parameters" {
        $colorCommand = & $colorModule { Get-Command Convert-DbaTimelineStatusColor }
        $colorCommand.Parameters["Status"].ParameterType | Should -Be ([string])
        $colorBinding = $colorCommand.ParameterSets.Parameters | Where-Object Name -eq Status
        $colorBinding.Position | Should -Be 0
        $colorBinding.IsMandatory | Should -BeTrue
        $colorBinding.ValueFromPipeline | Should -BeFalse
        $colorBinding.ValueFromPipelineByPropertyName | Should -BeFalse
        $colorCommand.Parameters.ContainsKey("EnableException") | Should -BeFalse
        $colorCommand.OutputType.Count | Should -Be 0
        Compare-Object (@($TestConfig.CommonParameters) + "Status") @($colorCommand.Parameters.Keys) | Should -BeNullOrEmpty
    }

    It "returns the exact color for all known statuses with case-insensitive matching" {
        foreach ($colorCase in @(
            @{ Input = "Failed"; Expected = "#FF3D3D" },
            @{ Input = "Succeeded"; Expected = "#36B300" },
            @{ Input = "Retry"; Expected = "#FFFF00" },
            @{ Input = "Canceled"; Expected = "#C2C2C2" },
            @{ Input = "In Progress"; Expected = "#00CCFF" },
            @{ Input = "fAiLeD"; Expected = "#FF3D3D" },
            @{ Input = "iN pRoGrEsS"; Expected = "#00CCFF" },
            @{ Input = [psobject]"FaIlEd"; Expected = "#FF3D3D" }
        )) {
            $colorRows = @(& $colorModule { param($value) Convert-DbaTimelineStatusColor -Status $value } $colorCase.Input)
            $colorRows.Count | Should -Be 1
            $colorRows[0] | Should -BeOfType System.String
            $colorRows[0] | Should -BeExactly $colorCase.Expected
        }
    }

    It "keeps whitespace significant and converts unknown scalar inputs" {
        foreach ($colorInput in @("Unknown", " Failed ", " ", 42, [decimal]1.5, [psobject]42, [datetime]"2026-10-21T01:02:03")) {
            $colorRows = @(& $colorModule { param($value) Convert-DbaTimelineStatusColor -Status $value } $colorInput)
            $colorRows.Count | Should -Be 1
            $colorRows[0] | Should -BeExactly "#FF00CC"
        }
        $colorCulture = [Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [Threading.Thread]::CurrentThread.CurrentCulture = New-Object Globalization.CultureInfo "fr-FR"
            (& $colorModule { Convert-DbaTimelineStatusColor -Status ([decimal]1.5) }) | Should -BeExactly "#FF00CC"
        } finally { [Threading.Thread]::CurrentThread.CurrentCulture = $colorCulture }
    }

    It "rejects null, empty and array inputs instead of returning a default color" {
        foreach ($colorInvalid in @(@{ Value = $null }, @{ Value = "" }, @{ Value = @() }, @{ Value = @("Failed") }, @{ Value = @("Failed", "Succeeded") })) {
            $colorCaught = $null
            $colorOutputs = New-Object "System.Collections.Generic.List[object]"
            try {
                & $colorModule { param($value) Convert-DbaTimelineStatusColor -Status $value } $colorInvalid.Value |
                    ForEach-Object { $colorOutputs.Add($PSItem) }
            } catch { $colorCaught = $PSItem }
            $colorOutputs.Count | Should -Be 0
            $colorCaught | Should -Not -BeNullOrEmpty
            $colorCaught.CategoryInfo.Category | Should -Be "InvalidData"
        }
    }

    It "rejects unused pipeline records and still emits its single end result" {
        $colorStreams = @(& $colorModule { 1, 2 | Convert-DbaTimelineStatusColor -Status "Failed" -ErrorAction Continue 2>&1 })
        $colorErrors = @($colorStreams | Where-Object { $PSItem -is [Management.Automation.ErrorRecord] })
        $colorValues = @($colorStreams | Where-Object { $PSItem -isnot [Management.Automation.ErrorRecord] })
        $colorErrors.Count | Should -Be 2
        foreach ($colorError in $colorErrors) {
            ($colorError.FullyQualifiedErrorId -split ",")[0] | Should -BeExactly "InputObjectNotBound"
            $colorError.CategoryInfo.Category | Should -Be "InvalidArgument"
        }
        $colorValues.Count | Should -Be 1
        $colorValues[0] | Should -BeExactly "#FF3D3D"
    }
}
