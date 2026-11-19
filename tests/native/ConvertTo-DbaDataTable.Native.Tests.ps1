#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: azure-sqldb N/A -- Converts in-memory objects to a DataTable without a database connection; the same output can be consumed by Azure-capable bulk writers.
param(
    $ModuleName = "dbatools",
    $CommandName = "ConvertTo-DbaDataTable",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- pure object conversion has no SupportsShouldProcess or external changes.
# NativeChecklist: multi-instance-failure N/A -- this converter opens no instance connections.
# NativeChecklist: sql2005 N/A -- Converts in-memory objects and opens no SQL Server connection.
Describe "Native ConvertTo-DbaDataTable" -Tag UnitTests {
    BeforeAll {
        function Invoke-NativeTableSchemaFault {
            param([string]$Fixture, [string]$Mode, [bool]$Raw = $false)
            $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $type = (Get-Command $CommandName -CommandType Cmdlet).ImplementingType
            $entry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList $CommandName, $type, $null
            $state.Commands.Add($entry)
            $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($state)
            $shell = [System.Management.Automation.PowerShell]::Create()
            $output = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
            try {
                $runspace.Open()
                $shell.Runspace = $runspace
                $body = {
                    param($Fixture, $Mode, $Raw)
                    if ($Fixture -eq 'getter') {
                        $first = [pscustomobject]@{ Good = 'first' }
                        $first | Add-Member -MemberType ScriptProperty -Name Broken -Value { throw 'native_getter_fault' }
                        $inputs = @($first, [pscustomobject]@{ Good = 'last'; Broken = 'healthy' })
                    } elseif ($Fixture -eq 'null-date-array') {
                        $first = & ([scriptblock]::Create(@'
class NativeNullDateArrayInput {
    [Dataplat.Dbatools.Utility.DbaDateTime[]] $Dates
    [string] $Good = 'first'
}
New-Object -TypeName NativeNullDateArrayInput
'@))
                        $property = $first.PSObject.Properties['Dates']
                        if ($property.TypeNameOfValue -ne 'Dataplat.Dbatools.Utility.DbaDateTime[]' -or
                            $null -ne $property.Value -or $null -ne [Type]::GetType($property.TypeNameOfValue)) {
                            throw 'Fixture did not reach the unresolved null date-array type.'
                        }
                        $inputs = @($first, [pscustomobject]@{ Dates = 'healthy'; Good = 'last' })
                    } else {
                        $first = New-Object System.Data.DataTable
                        $null = $first.Columns.Add('Id', [int])
                        $null = $first.Rows.Add(1)
                        $conflict = New-Object System.Data.DataTable
                        $null = $conflict.Columns.Add('Id', [string])
                        $null = $conflict.Rows.Add('second')
                        $last = New-Object System.Data.DataTable
                        $null = $last.Columns.Add('Id', [int])
                        $null = $last.Rows.Add(3)
                        $inputs = if ($Fixture -eq 'rows') { @($first.Rows[0], $conflict.Rows[0], $last.Rows[0]) }
                        else { @([pscustomobject]@{ Id = 'first' }, $first.Rows[0], [pscustomobject]@{ Id = 'last' }) }
                    }
                    $parameters = @{ EnableException = ($Mode -eq 'enable'); Raw = $Raw }
                    if ($Mode -eq 'erroraction') { $parameters.ErrorAction = 'Stop' }
                    $ErrorActionPreference = 'Continue'
                    if ($Mode -eq 'try') {
                        try { $inputs | ConvertTo-DbaDataTable @parameters; 'not caught' }
                        catch { [pscustomobject]@{ CaughtRecord = $PSItem } }
                    } else { $inputs | ConvertTo-DbaDataTable @parameters }
                    'next statement'
                }
                $null = $shell.AddScript($body.ToString()).AddArgument($Fixture).AddArgument($Mode).AddArgument($Raw)
                $stop = $null
                try { $null = $shell.Invoke($null, $output) } catch { $stop = $PSItem }
                [pscustomobject]@{ State = $shell.InvocationStateInfo.State.ToString(); Output = @($output); Errors = @($shell.Streams.Error); Warnings = @($shell.Streams.Warning); Stop = $stop }
            } finally { $shell.Dispose(); $runspace.Dispose() }
        }

        function Assert-NativeTableMergeFault {
            param([string]$Fixture)
            foreach ($mode in @('plain', 'try', 'enable', 'erroraction')) {
                $result = Invoke-NativeTableSchemaFault -Fixture $Fixture -Mode $mode
                $result.Warnings.Count | Should -Be 0
                if ($mode -eq 'erroraction') {
                    $result.State | Should -BeExactly 'Failed'
                    $result.Stop.Exception.InnerException | Should -BeOfType ([System.Management.Automation.ActionPreferenceStopException])
                    $result.Output.Count | Should -Be 0
                    $result.Output | Should -Not -Contain 'next statement'
                } else {
                    $result.State | Should -BeExactly 'Completed'
                    $result.Stop | Should -BeNullOrEmpty
                    $result.Output[-1] | Should -BeExactly 'next statement'
                }
                $tables = @($result.Output | Where-Object { $_ -is [System.Data.DataTable] })
                if ($mode -eq 'plain') {
                    $result.Output.Count | Should -Be 2
                    $tables.Count | Should -Be 1
                    $tables[0].Rows.Count | Should -Be 2
                    if ($Fixture -eq 'rows') {
                        $tables[0].Columns['Id'].DataType | Should -Be ([int])
                        @($tables[0].Rows | ForEach-Object Id) | Should -Be @(1, 3)
                    } else {
                        $tables[0].Columns['Id'].DataType | Should -Be ([string])
                        @($tables[0].Rows | ForEach-Object Id) | Should -Be @('first', 'last')
                    }
                } else { $tables.Count | Should -Be 0 }
                if ($mode -eq 'try') {
                    $result.Errors.Count | Should -Be 0
                    $result.Output.Count | Should -Be 2
                    $record = $result.Output[0].CaughtRecord
                } elseif ($mode -eq 'erroraction') {
                    $result.Errors.Count | Should -Be 0
                    $record = $result.Stop.Exception.InnerException.ErrorRecord
                } else {
                    $result.Errors.Count | Should -Be 1
                    $record = $result.Errors[0]
                    if ($mode -ne 'plain') { $result.Output.Count | Should -Be 1 }
                }
                $record | Should -Not -BeNullOrEmpty
                ($record.FullyQualifiedErrorId -split ',')[0] | Should -BeExactly 'DataException'
                $record.Exception | Should -BeOfType ([System.Management.Automation.MethodInvocationException])
                $record.Exception.InnerException | Should -BeOfType ([System.Data.DataException])
                $record.Exception.Message | Should -BeExactly 'Exception calling "Merge" with "1" argument(s): "<target>.Id and <source>.Id have conflicting properties: DataType property mismatch."'
                $record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::NotSpecified)
                $record.TargetObject | Should -BeNullOrEmpty
            }
        }

        function Invoke-NativeTableAssignmentFault {
            param([switch]$EnableException, [string]$ErrorActionMode = "Continue")
            $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $type = (Get-Command $CommandName -CommandType Cmdlet).ImplementingType
            $entry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList $CommandName, $type, $null
            $state.Commands.Add($entry)
            $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($state)
            $shell = [System.Management.Automation.PowerShell]::Create()
            $output = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $rows = @(
                [pscustomobject]@{ Size = [dbasize]1; Label = "first" }
                [pscustomobject]@{ Size = [dbasize]3000000000; Label = "overflow" }
                [pscustomobject]@{ Size = [dbasize]2; Label = "last" }
            )
            try {
                $runspace.Open()
                $shell.Runspace = $runspace
                # No surrounding script try in this runspace: Pester cannot alter the fault's continuation.
                $null = $shell.AddCommand($CommandName).AddParameter("InputObject", $rows).AddParameter("SizeType", "Int32").AddParameter("EnableException", $EnableException.IsPresent).AddParameter("ErrorAction", $ErrorActionMode)
                $stop = $null
                try { $null = $shell.Invoke($null, $output) }
                catch { $stop = $PSItem.Exception.InnerException }
                [pscustomobject]@{ State = $shell.InvocationStateInfo.State.ToString(); Output = @($output); Errors = @($shell.Streams.Error); Stop = $stop }
            } finally { $shell.Dispose(); $runspace.Dispose() }
        }
    }

    It "preserves prior and later DataRows after a schema conflict and honors all stopping modes" -Tag "NativeChecklist:enable-exception", "NativeChecklist:pipeline-multiple" {
        Assert-NativeTableMergeFault -Fixture rows
    }

    It "preserves object rows around a conflicting DataRow and honors all stopping modes" -Tag "NativeChecklist:enable-exception", "NativeChecklist:pipeline-multiple" {
        Assert-NativeTableMergeFault -Fixture mixed
    }

    It "keeps a throwing ScriptProperty as DBNull without inventing an error record" -Tag "NativeChecklist:pipeline-multiple" {
        # Both-edition pin probe: the getter produces no record, including inside a caller try.
        foreach ($raw in @($false, $true)) {
            foreach ($mode in @('plain', 'try', 'enable', 'erroraction')) {
                $result = Invoke-NativeTableSchemaFault -Fixture getter -Mode $mode -Raw $raw
                $result.State | Should -BeExactly 'Completed'
                $result.Stop | Should -BeNullOrEmpty
                $result.Errors.Count | Should -Be 0
                $result.Warnings.Count | Should -Be 0
                $result.Output[-1] | Should -BeExactly 'next statement'
                $tables = @($result.Output | Where-Object { $_ -is [System.Data.DataTable] })
                $tables.Count | Should -Be 1
                $tables[0].Rows.Count | Should -Be 2
                $tables[0].Columns['Broken'].DataType | Should -Be ([string])
                $tables[0].Rows[0].Broken | Should -BeOfType ([DBNull])
                $tables[0].Rows[0].Good | Should -BeExactly 'first'
                $tables[0].Rows[1].Broken | Should -BeExactly 'healthy'
                $tables[0].Rows[1].Good | Should -BeExactly 'last'
                if ($mode -eq 'try') {
                    $result.Output.Count | Should -Be 3
                    $result.Output[1] | Should -BeExactly 'not caught'
                } else { $result.Output.Count | Should -Be 2 }
            }
        }
    }

    It "surfaces an unresolved null date array column type and preserves the Raw control" -Tag "NativeChecklist:enable-exception", "NativeChecklist:switch-false", "NativeChecklist:pipeline-multiple" {
        foreach ($raw in @($false, $true)) {
            foreach ($mode in @('plain', 'try', 'enable', 'erroraction')) {
                $result = Invoke-NativeTableSchemaFault -Fixture null-date-array -Mode $mode -Raw $raw
                $result.Warnings.Count | Should -Be 0
                $tables = @($result.Output | Where-Object { $_ -is [System.Data.DataTable] })
                if ($raw -or $mode -eq 'plain') {
                    $result.State | Should -BeExactly 'Completed'
                    $result.Stop | Should -BeNullOrEmpty
                    $result.Output[-1] | Should -BeExactly 'next statement'
                    $tables.Count | Should -Be 1
                    $tables[0].Rows.Count | Should -Be 2
                    $tables[0].Columns['Dates'].DataType | Should -Be ([string])
                    $tables[0].Rows[0].Dates | Should -BeOfType ([DBNull])
                    $tables[0].Rows[0].Good | Should -BeExactly 'first'
                    $tables[0].Rows[1].Dates | Should -BeExactly 'healthy'
                    $tables[0].Rows[1].Good | Should -BeExactly 'last'
                } else { $tables.Count | Should -Be 0 }
                if ($raw) {
                    $result.Errors.Count | Should -Be 0
                    if ($mode -eq 'try') {
                        $result.Output.Count | Should -Be 3
                        $result.Output[1] | Should -BeExactly 'not caught'
                    } else { $result.Output.Count | Should -Be 2 }
                    continue
                }
                if ($mode -eq 'try') {
                    $result.Errors.Count | Should -Be 0
                    $result.Stop | Should -BeNullOrEmpty
                    $result.Output.Count | Should -Be 2
                    $result.Output[-1] | Should -BeExactly 'next statement'
                    $record = $result.Output[0].CaughtRecord
                } elseif ($mode -eq 'erroraction' -and $result.Stop) {
                    # An ActionPreferenceStop can escape the hosting Invoke rather than its error stream.
                    $result.State | Should -BeExactly 'Failed'
                    $result.Output.Count | Should -Be 0
                    $record = $result.Stop.Exception.InnerException.ErrorRecord
                } else {
                    $result.Errors.Count | Should -Be 1
                    $record = $result.Errors[0]
                    if ($mode -eq 'enable') {
                        $result.Output.Count | Should -Be 1
                        $result.Output[0] | Should -BeExactly 'next statement'
                    }
                }
                $record | Should -Not -BeNullOrEmpty
                ($record.FullyQualifiedErrorId -split ',')[0] | Should -BeExactly 'ExceptionWhenSetting'
                $record.Exception | Should -BeOfType ([System.Management.Automation.SetValueInvocationException])
                $record.Exception.Message | Should -BeExactly 'Exception setting "DataType": "Column requires a valid DataType."'
                $record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::NotSpecified)
                $record.TargetObject | Should -BeNullOrEmpty
            }
        }
    }

    It "converts a nested registered server carrying the caller ToString method" {
        # Pin public/Get-DbaRegServer.ps1:264 creates this RegisteredServer type, :271 decorates ServerName,
        # and :382 attaches the exact ScriptMethod below. No registration or SQL connection is needed.
        $group = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup -ArgumentList "NativeToString"
        $registered = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer -ArgumentList $group, "NativeRegistration"
        $registered | Add-Member -MemberType NoteProperty -Name ServerName -Value "native-server" -Force
        $registered | Add-Member -MemberType ScriptMethod -Name ToString -Value { $this.ServerName } -Force
        $inputRow = [pscustomobject]@{ Server = $registered }
        $property = $inputRow.PSObject.Properties["Server"]
        # Pin public/ConvertTo-DbaDataTable.ps1:376 uses the scalar Length, :388 calls ToString,
        # :397 retains the original property value, and :401 assigns it to the string DataColumn.
        $property.Value.Length | Should -BeGreaterThan 0
        $property.Value.ToString() | Should -BeExactly "native-server"
        $expected = New-Object System.Data.DataTable
        $null = $expected.Columns.Add("Server", [string])
        $expectedRow = $expected.NewRow()
        $expectedRow.Item("Server") = $property.Value
        $null = $expected.Rows.Add($expectedRow)
        $converted = ConvertTo-DbaDataTable -InputObject $inputRow -EnableException
        $converted.Rows.Count | Should -Be 1
        $converted.Rows[0].Server | Should -BeExactly $expected.Rows[0].Server
    }

    It "preserves ordinary dotnet ToString for a nested value without an ETS override" {
        $value = New-Object System.Text.StringBuilder -ArgumentList "native-plain-value"
        $converted = ConvertTo-DbaDataTable -InputObject ([pscustomobject]@{ Value = $value }) -EnableException
        $converted.Rows.Count | Should -Be 1
        $converted.Rows[0].Value | Should -BeExactly $value.ToString()
    }

    It "preserves mixed DataRow and object inputs without creating duplicate columns" {
        $source = New-Object System.Data.DataTable
        $null = $source.Columns.Add("Id", [int])
        $null = $source.Columns.Add("Label", [string])
        $null = $source.Rows.Add(1, "row")
        $objectRow = [pscustomobject]@{ Id = 2; Label = "object" }
        $converted = @($source.Rows[0], $objectRow) | ConvertTo-DbaDataTable -EnableException
        $converted.Rows.Count | Should -Be 2
        $converted.Columns.Count | Should -Be 2
        $converted.Columns["Id"].DataType | Should -Be ([int])
        $converted.Rows[0].Label | Should -BeExactly "row"
        $converted.Rows[1].Id | Should -Be 2
        $converted.Rows[1].Label | Should -BeExactly "object"
    }

    It "copies only supplied DataRows and preserves repeated rows in input order" -Tag "NativeChecklist:pipeline-multiple" {
        $source = New-Object System.Data.DataTable
        $null = $source.Columns.Add("Id", [int])
        $null = $source.Columns.Add("Label", [string])
        $null = $source.Rows.Add(1, "first")
        $null = $source.Rows.Add(2, "second")
        $null = $source.Rows.Add(3, "not-selected")
        $selected = ConvertTo-DbaDataTable -InputObject $source.Rows[1]
        $selected.Rows.Count | Should -Be 1
        $selected.Rows[0].Id | Should -Be 2
        $repeated = @($source.Rows[1], $source.Rows[0], $source.Rows[1]) | ConvertTo-DbaDataTable
        $repeated.Rows.Count | Should -Be 3
        ($repeated.Rows | ForEach-Object Id) -join "," | Should -Be "2,1,2"
        $repeated.Columns["Id"].DataType | Should -Be ([int])
        $source.Rows.Count | Should -Be 3
    }

    It "preserves repeated input rows even when the source table has a primary key" {
        $source = New-Object System.Data.DataTable
        $null = $source.Columns.Add("Id", [int])
        $source.PrimaryKey = @($source.Columns["Id"])
        $null = $source.Rows.Add(1)
        $converted = @($source.Rows[0], $source.Rows[0], $source.Rows[0]) | ConvertTo-DbaDataTable
        $converted.Rows.Count | Should -Be 3
        ($converted.Rows | ForEach-Object Id) -join "," | Should -Be "1,1,1"
        $source.PrimaryKey.Count | Should -Be 1
    }

    It "keeps null rows and typed columns with explicit false switches" -Tag "NativeChecklist:switch-false", "NativeChecklist:pipeline-multiple" {
        $converted = @([PSCustomObject]@{ Number = 1 }, $null, [PSCustomObject]@{ Number = 2 }) | ConvertTo-DbaDataTable -IgnoreNull:$false -Raw:$false -EnableException:$false
        $converted.Rows.Count | Should -Be 3
        $converted.Columns["Number"].DataType | Should -Be ([int])
        $converted.Rows[1].Number | Should -BeOfType ([DBNull])
        $converted.Rows[2].Number | Should -Be 2
    }

    It "throws instead of warning when an ordinary cell conversion fails with EnableException" -Tag "NativeChecklist:enable-exception" {
        $inputRows = @([PSCustomObject]@{ Number = 1 }, [PSCustomObject]@{ Number = "not-an-integer" })
        $failure = $null
        try {
            $null = ConvertTo-DbaDataTable -InputObject $inputRows -EnableException -WarningAction SilentlyContinue
        } catch {
            $failure = $_
        }
        $failure | Should -Not -BeNullOrEmpty
        $failure.FullyQualifiedErrorId | Should -Match "dbatools_ConvertTo-DbaDataTable"
    }

    It "lets a caller try catch special-value assignment faults with the upstream error identity" -Tag "NativeChecklist:enable-exception" {
        $first = [PSCustomObject]@{ Size = [dbasize]1 }
        $overflow = [PSCustomObject]@{ Size = [dbasize]3000000000 }
        $failure = $null
        $result = $null
        try {
            $result = ConvertTo-DbaDataTable -InputObject @($first, $overflow) -SizeType Int32 -EnableException:$false
        } catch {
            $failure = $_
        }
        $result | Should -BeNullOrEmpty
        $failure | Should -Not -BeNullOrEmpty
        $failure.Exception | Should -BeOfType ([System.Management.Automation.SetValueInvocationException])
        $failure.FullyQualifiedErrorId | Should -BeLike "ExceptionWhenSetting*"
        $failure.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::NotSpecified)
        $failure.TargetObject | Should -BeNullOrEmpty
    }

    It "reports special-value assignment faults and retains later cells and rows outside a caller try" -Tag "NativeChecklist:switch-false", "NativeChecklist:pipeline-multiple" {
        # Pin :386 has no local catch, then :425 adds the row and end :436 emits the table.
        $result = Invoke-NativeTableAssignmentFault -EnableException:$false
        $result.State | Should -BeExactly "Completed"
        $result.Stop | Should -BeNullOrEmpty
        $result.Errors.Count | Should -Be 1
        $result.Errors[0].Exception | Should -BeOfType ([System.Management.Automation.SetValueInvocationException])
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike "ExceptionWhenSetting*"
        $result.Errors[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::NotSpecified)
        $result.Errors[0].TargetObject | Should -BeNullOrEmpty
        $result.Output.Count | Should -Be 1
        $table = $result.Output[0]
        ($table -is [System.Data.DataTable]) | Should -BeTrue
        $table.Columns["Size"].DataType | Should -Be ([int])
        $table.Rows.Count | Should -Be 3
        $table.Rows[0].Size | Should -Be 1
        $table.Rows[1].Size | Should -BeOfType ([DBNull])
        $table.Rows[1].Label | Should -BeExactly "overflow"
        $table.Rows[2].Size | Should -Be 2
        $table.Rows[2].Label | Should -BeExactly "last"
    }

    It "stops special-value assignment faults with EnableException or ErrorAction Stop outside a caller try" -Tag "NativeChecklist:enable-exception" {
        foreach ($mode in @(@{ EnableException = $true; ErrorActionMode = "Continue" }, @{ EnableException = $false; ErrorActionMode = "Stop" })) {
            $result = Invoke-NativeTableAssignmentFault @mode
            $result.State | Should -BeExactly "Failed"
            $result.Output.Count | Should -Be 0
            $result.Stop | Should -Not -BeNullOrEmpty
            $result.Stop.ErrorRecord.FullyQualifiedErrorId | Should -BeLike "ExceptionWhenSetting*"
            $result.Stop.ErrorRecord.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::NotSpecified)
        }
    }
}
