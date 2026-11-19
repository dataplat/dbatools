#nullable enable

namespace Dataplat.Dbatools.Commands;

// Hop script constant (the verbatim retired PS body) - split out per the repo 400-line file limit.
public sealed partial class NewDbaDbTableCommand
{

    // PS: the process block VERBATIM, dot-sourced so its three early returns exit only the body.
    // Edits: five Test-Bound probes become carried boundness flags, the one $Pscmdlet gate routes to
    // $__realCmdlet, and -FunctionName is stamped on the message calls.
    //
    // THE PREAMBLE REPLACES $PSBoundParameters with the CALLER's table. Source :512 iterates it and
    // assigns each key onto the SMO Table; the hop's own $PSBoundParameters would carry the plumbing
    // and 49 null placeholders, nulling real properties and then failing on $object.__realCmdlet.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Name, $Schema, $ColumnMap, $ColumnObject, $Passthru, $InputObject, $EnableException, $__boundParameters, $__state, $__boundSqlInstance, $__boundDatabase, $__boundName, $__boundSchema, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__verbosePref, $__debugPref, $__errorActionPref, $__warningPref)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [String[]]$Database, [String]$Name, [String]$Schema, [hashtable[]]$ColumnMap, [Microsoft.SqlServer.Management.Smo.Column[]]$ColumnObject, $Passthru, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__boundParameters, $__state, $__boundSqlInstance, $__boundDatabase, $__boundName, $__boundSchema, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__verbosePref, $__debugPref, $__errorActionPref, $__warningPref)
    if ($null -ne $__verbosePref) { $VerbosePreference = $__verbosePref }
    if ($null -ne $__debugPref) { $DebugPreference = $__debugPref }
    if ($null -ne $__errorActionPref) { $ErrorActionPreference = $__errorActionPref }
    if ($null -ne $__warningPref) { $WarningPreference = $__warningPref }

    # the body projects the CALLER's bound parameters onto the SMO Table (source :512); the hop's own
    # automatic $PSBoundParameters would carry plumbing and null placeholders instead
    $PSBoundParameters = $__boundParameters

    # FAILURE-PATH CROSS-RECORD CARRY (codex r1). $object (:503) and $schemaObject (:586) are read by
    # the catch cleanup at :617-626, which calls .Drop() on them. If the try throws BEFORE the
    # assignment - New-Object Smo.Table at :503 is the obvious case - the source still holds the
    # PREVIOUS record's objects in its persistent process scope, so the cleanup drops the previously
    # created table and schema. The hop's fresh scope would instead see $null and merely warn.
    # Carried with Assigned flags so a first record leaves them genuinely undefined, as the source does.
    if ($null -ne $__state -and $__state.ObjectAssigned) { $object = $__state.Object }
    if ($null -ne $__state -and $__state.SchemaObjectAssigned) { $schemaObject = $__state.SchemaObject }
    # PARAMETER-MUTATION CARRY (codex r2). $Name (:483) and $Schema (:481) are rewritten by the
    # two-part-name parsing, and NEITHER is the pipeline-bound parameter - only $InputObject is - so
    # the binder never rewrites them and the SOURCE keeps the parsed values for every later record.
    # Measured: a non-pipeline parameter mutated in process yields a, ax, axx over three records.
    # Reachable divergence: with -Name "[my.table]", record 1 parses to the bracket-quoted name
    # "my.table"; the source's record 2 then re-parses that UNQUOTED value as schema "my" + table
    # "table" and creates the table in the wrong schema, while a fresh hop scope re-parses the
    # original and gets it right. The port must reproduce the source, so both carry.
    if ($null -ne $__state -and $__state.NameAssigned) { $Name = $__state.Name }
    if ($null -ne $__state -and $__state.SchemaAssigned) { $Schema = $__state.Schema }

    . {
        # W2-151: this `. { }` dot-source runs as its own scriptblock invocation, so the automatic
        # $PSBoundParameters is RE-INITIALIZED to empty here (measured: populated at the preamble,
        # empty at the projection loop below). Re-assert the caller's reconstructed table INSIDE the
        # block so the "foreach ($param in $PSBoundParameters.Keys) { $object.$param = ... }"
        # projection (IsNode/IsEdge/etc.) sees it. $__boundParameters is visible here (dot-source
        # shares the parent scope's variables; only the $PSBoundParameters automatic is re-scoped).
        $PSBoundParameters = $__boundParameters
        if (($__boundSqlInstance)) {
            if ((-not $__boundDatabase) -or (-not $__boundName)) {
                Stop-Function -Message "You must specify one or more databases and one Name when using the SqlInstance parameter." -FunctionName New-DbaDbTable
                return
            }
        }

        # Parse the Name parameter to handle bracket-quoted names and two-part names like [schema].[table]
        if ($__boundName) {
            $parsedName = Get-ObjectNameParts -ObjectName $Name
            if ($parsedName.Parsed) {
                if ($parsedName.Database) {
                    Stop-Function -Message "The -Name parameter only accepts one- or two-part names. Specify the database separately with -Database or by piping in a database object." -FunctionName New-DbaDbTable
                    return
                }
                if ($parsedName.Schema -and -not ($__boundSchema)) {
                    $Schema = $parsedName.Schema
                }
                $Name = $parsedName.Name
            } else {
                Stop-Function -Message "Could not parse -Name '$Name' as a valid object name." -FunctionName New-DbaDbTable
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            if ($__realCmdlet.ShouldProcess("Creating new table [$Schema].[$Name] in $db on $server")) {
                # Test if table already exists. This ways we can drop the table if part of the creation fails.
                $existingTable = $db.tables | Where-Object { $_.Schema -eq $Schema -and $_.Name -eq $Name }
                if ($existingTable) {
                    Stop-Function -Message "Table [$Schema].[$Name] already exists in $db on $server" -Continue -FunctionName New-DbaDbTable
                }
                try {
                    $object = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Table $db, $Name, $Schema

                    # Get common parameters dynamically
                    $commonParams = [System.Management.Automation.PSCmdlet]::CommonParameters
                    $commonParams += [System.Management.Automation.PSCmdlet]::OptionalCommonParameters

                    $excludeParams = @(
                        'SqlInstance', 'SqlCredential', 'Database', 'Name', 'Schema',
                        'ColumnMap', 'ColumnObject', 'InputObject', 'EnableException', 'Passthru'
                    ) + $commonParams

                    foreach ($param in $PSBoundParameters.Keys) {
                        if ($param -notin $excludeParams) {
                            # IsNode and IsEdge are only supported in SQL Server 2017+ (version 14+)
                            if ($param -in 'IsNode', 'IsEdge' -and $server.VersionMajor -lt 14) {
                                Write-Message -Level Warning -Message "Parameter $param is only supported on SQL Server 2017 and above. Current version is $($server.VersionMajor). Skipping." -FunctionName New-DbaDbTable -ModuleName "dbatools"
                                continue
                            }
                            $object.$param = $PSBoundParameters[$param]
                        }
                    }

                    foreach ($column in $ColumnObject) {
                        $object.Columns.Add($column)
                    }

                    foreach ($column in $ColumnMap) {
                        $sqlDbType = [Microsoft.SqlServer.Management.Smo.SqlDataType]$($column.Type)
                        if ($sqlDbType -in @('VarBinary', 'VarChar', 'NVarChar', 'Char', 'NChar')) {
                            if ($column.MaxLength -gt 0) {
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType, $column.MaxLength
                            } else {
                                $sqlDbType = [Microsoft.SqlServer.Management.Smo.SqlDataType]"$($column.Type)Max"
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType
                            }
                        } elseif ($sqlDbType -eq 'Decimal') {
                            if ($column.MaxLength -gt 0) {
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType, $column.MaxLength
                            } elseif ($column.Precision -gt 0) {
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType, $column.Precision, $column.Scale
                            } else {
                                $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType
                            }
                        } else {
                            $dataType = New-Object Microsoft.SqlServer.Management.Smo.DataType $sqlDbType
                        }
                        $sqlColumn = New-Object Microsoft.SqlServer.Management.Smo.Column $object, $column.Name, $dataType
                        $sqlColumn.Nullable = $column.Nullable

                        if ($column.DefaultName) {
                            $dfName = $column.DefaultName
                        } else {
                            $dfName = "DF_$name`_$($column.Name)"
                        }
                        if ($column.DefaultExpression) {
                            # override the default that would add quotes to an expression
                            $sqlColumn.AddDefaultConstraint($dfName).Text = $column.DefaultExpression
                        } elseif ($column.DefaultString) {
                            # override the default that would not add quotes to a date string
                            $sqlColumn.AddDefaultConstraint($dfName).Text = "'$($column.DefaultString)'"
                        } elseif ($column.Default) {
                            if ($sqlDbType -in @('NVarchar', 'NChar', 'NVarcharMax', 'NCharMax')) {
                                $sqlColumn.AddDefaultConstraint($dfName).Text = "N'$($column.Default)'"
                            } elseif ($sqlDbType -in @('Varchar', 'Char', 'VarcharMax', 'CharMax')) {
                                $sqlColumn.AddDefaultConstraint($dfName).Text = "'$($column.Default)'"
                            } else {
                                $sqlColumn.AddDefaultConstraint($dfName).Text = $column.Default
                            }
                        }

                        if ($column.Identity) {
                            $sqlColumn.Identity = $true
                            if ($column.IdentitySeed) {
                                $sqlColumn.IdentitySeed = $column.IdentitySeed
                            }
                            if ($column.IdentityIncrement) {
                                $sqlColumn.IdentityIncrement = $column.IdentityIncrement
                            }
                        }
                        $object.Columns.Add($sqlColumn)
                    }

                    # user has specified a schema that does not exist yet
                    $schemaObject = $null
                    if (-not ($db | Get-DbaDbSchema -Schema $Schema -IncludeSystemSchemas)) {
                        Write-Message -Level Verbose -Message "Schema $Schema does not exist in $db and will be created." -FunctionName New-DbaDbTable -ModuleName "dbatools"
                        $schemaObject = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Schema $db, $Schema
                    }

                    if ($Passthru) {
                        $ScriptingOptionsObject = New-DbaScriptingOption
                        $ScriptingOptionsObject.ContinueScriptingOnError = $false
                        $ScriptingOptionsObject.DriAllConstraints = $true

                        if ($schemaObject) {
                            $schemaObject.Script($ScriptingOptionsObject)
                        }

                        $object.Script($ScriptingOptionsObject)
                    } else {
                        if ($schemaObject) {
                            $null = Invoke-Create -Object $schemaObject
                        }
                        $null = Invoke-Create -Object $object
                        $db.Tables.Refresh()
                    }
                    $db | Get-DbaDbTable -Table "[$Schema].[$Name]"
                } catch {
                    $exception = $_
                    Write-Message -Level Verbose -Message "Failed to create table or failure while adding constraints. Will try to remove table (and schema)." -FunctionName New-DbaDbTable -ModuleName "dbatools"
                    try {
                        $object.Refresh()
                        if ($object.State -ne 'Dropped') {
                            $object.Drop()
                        }
                        if ($schemaObject) {
                            $schemaObject.Refresh()
                            if ($schemaObject.State -ne 'Dropped') {
                                $schemaObject.Drop()
                            }
                        }
                    } catch {
                        Write-Message -Level Warning -Message "Failed to drop table: $_. Maybe table still exists." -FunctionName New-DbaDbTable -ModuleName "dbatools"
                    }
                    Stop-Function -Message "Failure" -ErrorRecord $exception -Continue -FunctionName New-DbaDbTable
                }
            }
        }
    }

    $__ob = Get-Variable -Name object -Scope 0 -ErrorAction Ignore
    $__so = Get-Variable -Name schemaObject -Scope 0 -ErrorAction Ignore
    $__nm = Get-Variable -Name Name -Scope 0 -ErrorAction Ignore
    $__sc = Get-Variable -Name Schema -Scope 0 -ErrorAction Ignore
    @{ __newDbaDbTableProcess = @{
        ObjectAssigned       = [bool]$__ob
        Object               = $(if ($__ob) { $__ob.Value } else { $null })
        SchemaObjectAssigned = [bool]$__so
        SchemaObject         = $(if ($__so) { $__so.Value } else { $null })
        NameAssigned         = [bool]$__nm
        Name                 = $(if ($__nm) { $__nm.Value } else { $null })
        SchemaAssigned       = [bool]$__sc
        Schema               = $(if ($__sc) { $__sc.Value } else { $null })
    } }
} $SqlInstance $SqlCredential $Database $Name $Schema $ColumnMap $ColumnObject $Passthru $InputObject $EnableException $__boundParameters $__state $__boundSqlInstance $__boundDatabase $__boundName $__boundSchema $__realCmdlet $__boundWhatIf $__boundConfirm $__verbosePref $__debugPref $__errorActionPref $__warningPref @__commonParameters 3>&1 2>&1
""";
}
