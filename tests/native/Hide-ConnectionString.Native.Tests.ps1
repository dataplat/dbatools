#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Hide-ConnectionString",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Private connection string masking behavior" {
    BeforeAll {
        $maskModule = Get-Module dbatools | Where-Object ModuleType -eq Script
    }

    It "preserves optional scalar metadata" {
        $maskCommand = & $maskModule { Get-Command Hide-ConnectionString }
        $maskCommand.Parameters["ConnectionString"].ParameterType | Should -Be ([string])
        $maskBinding = $maskCommand.ParameterSets.Parameters | Where-Object Name -eq ConnectionString
        $maskBinding.Position | Should -Be 0
        $maskBinding.IsMandatory | Should -BeFalse
        $maskBinding.ValueFromPipeline | Should -BeFalse
        $maskBinding.ValueFromPipelineByPropertyName | Should -BeFalse
        $maskCommand.OutputType.Count | Should -Be 0
        Compare-Object (@($TestConfig.CommonParameters) + "ConnectionString") @($maskCommand.Parameters.Keys) | Should -BeNullOrEmpty
    }

    It "normalizes aliases and masks nonempty passwords without exposing fixture secrets" {
        foreach ($maskCase in @(
            @{ Input = "server=fixture-server"; Expected = "Data Source=fixture-server" },
            @{ Input = "data source=fixture-server;integrated security=sspi;initial catalog=fixture-db"; Expected = "Data Source=fixture-server;Initial Catalog=fixture-db;Integrated Security=True" },
            @{ Input = "server=fixture-server;user id=fixture-user;password=synthetic-password"; Expected = "Data Source=fixture-server;User ID=fixture-user;Password=********" },
            @{ Input = "server=fixture-server;pwd="; Expected = "Data Source=fixture-server" },
            @{ Input = "server=fixture-server;pwd='synthetic;password'"; Expected = "Data Source=fixture-server;Password=********" },
            @{ Input = "server=fixture-server;Password=first-synthetic;pwd=last-synthetic"; Expected = "Data Source=fixture-server;Password=********" },
            @{ Input = [psobject]"server=fixture-server"; Expected = "Data Source=fixture-server" }
        )) {
            $maskRows = @(& $maskModule { param($value) Hide-ConnectionString -ConnectionString $value } $maskCase.Input)
            $maskRows.Count | Should -Be 1
            $maskRows[0] | Should -BeOfType System.String
            $maskRows[0] | Should -BeExactly $maskCase.Expected
        }
    }

    It "returns one empty string for omitted or empty inputs and the fixed fallback for malformed scalars" {
        $maskOmitted = @(& $maskModule { Hide-ConnectionString })
        $maskOmitted.Count | Should -Be 1
        $maskOmitted[0] | Should -BeExactly ""
        foreach ($maskCase in @(
            @{ Input = $null; Expected = "" }, @{ Input = ""; Expected = "" }, @{ Input = " "; Expected = "" },
            @{ Input = "not-a-connection-string"; Expected = "Failed to mask the connection string" },
            @{ Input = "unknown-key=fixture"; Expected = "Failed to mask the connection string" },
            @{ Input = 42; Expected = "Failed to mask the connection string" },
            @{ Input = [psobject]42; Expected = "Failed to mask the connection string" },
            @{ Input = [decimal]1.5; Expected = "Failed to mask the connection string" }
        )) {
            $maskRows = @(& $maskModule { param($value) Hide-ConnectionString -ConnectionString $value } $maskCase.Input)
            $maskRows.Count | Should -Be 1
            $maskRows[0] | Should -BeOfType System.String
            $maskRows[0] | Should -BeExactly $maskCase.Expected
        }
    }

    It "rejects all array shapes before producing output" {
        foreach ($maskInvalid in @(
            @{ Value = @() }, @{ Value = @("server=fixture-server") },
            @{ Value = @("server=fixture-one", "server=fixture-two") },
            @{ Value = @(@("server=fixture-one", "server=fixture-two"), "server=fixture-three") }
        )) {
            $maskCaught = $null
            $maskOutputs = New-Object "System.Collections.Generic.List[object]"
            try {
                & $maskModule { param($value) Hide-ConnectionString -ConnectionString $value } $maskInvalid.Value |
                    ForEach-Object { $maskOutputs.Add($PSItem) }
            } catch { $maskCaught = $PSItem }
            $maskOutputs.Count | Should -Be 0
            $maskCaught | Should -Not -BeNullOrEmpty
            ($maskCaught.FullyQualifiedErrorId -split ",")[0] | Should -BeExactly "ParameterArgumentTransformationError"
            $maskCaught.CategoryInfo.Category | Should -Be "InvalidData"
            $maskCaught.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.ParameterBindingArgumentTransformationException"
            $maskCaught.Exception.Message | Should -BeExactly "Cannot process argument transformation on parameter 'ConnectionString'. Cannot convert value to type System.String."
        }
    }

    It "rejects unused pipeline records and emits the single bound end result" {
        $maskStreams = @(& $maskModule { 1, 2 | Hide-ConnectionString -ConnectionString "server=fixture-server" -ErrorAction Continue 2>&1 })
        $maskErrors = @($maskStreams | Where-Object { $PSItem -is [Management.Automation.ErrorRecord] })
        $maskValues = @($maskStreams | Where-Object { $PSItem -isnot [Management.Automation.ErrorRecord] })
        $maskErrors.Count | Should -Be 2
        foreach ($maskError in $maskErrors) {
            ($maskError.FullyQualifiedErrorId -split ",")[0] | Should -BeExactly "InputObjectNotBound"
            $maskError.CategoryInfo.Category | Should -Be "InvalidArgument"
        }
        $maskValues.Count | Should -Be 1
        $maskValues[0] | Should -BeExactly "Data Source=fixture-server"
    }
}
