#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Converts PowerShell objects into .NET DataTable objects for bulk SQL Server operations
/// </summary>
[Cmdlet(VerbsData.ConvertTo, "DbaDataTable")]
[OutputType(typeof(object[]))]
public sealed class ConvertToDbaDataTableCommand : DbaBaseCmdlet
{
    /// <summary>PowerShell objects to convert into a DataTable with proper SQL Server-compatible column types.</summary>
    [Parameter(Position = 0, Mandatory = true, ValueFromPipeline = true)]
    [AllowNull]
    public PSObject?[]? InputObject { get; set; }

    /// <summary>Controls how TimeSpan and DbaTimeSpan objects are converted for database storage.</summary>
    [Parameter]
    [PsStringCast]
    [ValidateSet("Ticks", "TotalDays", "TotalHours", "TotalMinutes", "TotalSeconds", "TotalMilliseconds", "String")]
    [ValidateNotNullOrEmpty]
    public string TimeSpanType { get; set; } = "TotalMilliseconds";

    /// <summary>Controls how DbaSize objects (file sizes, database sizes) are converted for database storage.</summary>
    [Parameter]
    [PsStringCast]
    [ValidateSet("Int64", "Int32", "String")]
    public string SizeType { get; set; } = "Int64";

    /// <summary>Excludes null objects from the DataTable instead of creating empty rows.</summary>
    [Parameter]
    public SwitchParameter IgnoreNull { get; set; }

    /// <summary>Forces all DataTable columns to be strings instead of detecting proper data types.</summary>
    [Parameter]
    public SwitchParameter Raw { get; set; }

    // PS: $types in Convert-Type — the accepted column types; everything else becomes a string.
    private static readonly string[] AcceptedTypes =
    {
        "System.Int32",
        "System.UInt32",
        "System.Int16",
        "System.UInt16",
        "System.Int64",
        "System.UInt64",
        "System.Decimal",
        "System.Single",
        "System.Double",
        "System.Byte",
        "System.Byte[]",
        "System.SByte",
        "System.Boolean",
        "System.DateTime",
        "System.Guid",
        "System.Char"
    };

    private DataTable _datatable = null!;
    private List<string> _columns = null!;
    private List<string> _specialColumns = null!;
    private Dictionary<string, string> _specialColumnsType = null!;
    private bool _shouldCreateColumns;

    // PS: Convert-Type returns @{ type; Value; Special; SpecialType }.
    private sealed class ConvertedType
    {
        public string TypeName = "System.String";
        public object? Value;
        public bool Special;
        public string SpecialType = "";
    }

    protected override void BeginProcessing()
    {
        // PS: Write-Message -Level Debug -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"
        WriteMessage(MessageLevel.Debug, string.Format("Bound parameters: {0}", string.Join(", ", MyInvocation.BoundParameters.Keys)));
        WriteMessage(MessageLevel.Debug, string.Format("TimeSpanType = {0} | SizeType = {1}", TimeSpanType, SizeType));

        _datatable = new DataTable();
        _columns = new List<string>();
        _specialColumns = new List<string>();
        // PS: @{ } hashtable literals key case-insensitively with an EDITION-DEPENDENT comparer:
        // current-culture on Windows PowerShell (net472), ordinal on PowerShell 7 (net8.0).
        _specialColumnsType = new Dictionary<string, string>(Environment.Version.Major == 4
            ? StringComparer.CurrentCultureIgnoreCase : StringComparer.OrdinalIgnoreCase);
        _shouldCreateColumns = true;
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // PS: if ($null -eq $InputObject) — a directly bound or piped $null adds one empty
        // row (unless IgnoreNull) and only ends the current process block.
        if (InputObject is null)
        {
            if (!IgnoreNull.ToBool())
            {
                DataRow nullRow = _datatable.NewRow();
                _datatable.Rows.Add(nullRow);
            }
            return;
        }

        foreach (PSObject? element in InputObject)
        {
            if (element is null)
            {
                if (!IgnoreNull.ToBool())
                {
                    DataRow nullRow = _datatable.NewRow();
                    _datatable.Rows.Add(nullRow);
                }
                continue;
            }

            // Keep the source's exact DataRow branch and schema metadata, but copy only
            // the supplied row. Importing its entire table and deduplicating loses input data.
            if (element.BaseObject is DataRow inputRow && PsString.Eq(inputRow.GetType().FullName, "System.Data.DataRow"))
            {
                DataTable inputSchema = inputRow.Table.Clone();
                DataTable mergeSchema = inputSchema.DefaultView.ToTable(false);
                try
                {
                    _datatable.Merge(mergeSchema);
                }
                catch (Exception exception) when (exception is not PipelineStoppedException)
                {
                    MethodInvocationException wrapped = new MethodInvocationException(string.Format(
                        "Exception calling \"Merge\" with \"1\" argument(s): \"{0}\"", exception.Message), exception);
                    ErrorRecord record = new ErrorRecord(wrapped, exception.GetType().Name, ErrorCategory.NotSpecified, null);
                    if (EnableException.ToBool())
                    {
                        // caller-try: terminate -- -EnableException requests a stop at the failed merge.
                        ThrowTerminatingError(record); // style-ok: cs-raw-streams preserve the pinned Merge error record
                    }
                    StatementFault.Surface(this, record);
                    continue;
                }
                DataRow copiedRow = _datatable.NewRow();
                foreach (DataColumn column in inputRow.Table.Columns)
                {
                    copiedRow[column.ColumnName] = inputRow[column];
                }
                _datatable.Rows.Add(copiedRow);
                _columns.Clear();
                foreach (DataColumn column in _datatable.Columns)
                {
                    _columns.Add(column.ColumnName);
                }
                _shouldCreateColumns = false;
                continue;
            }

            DataRow datarow = _datatable.NewRow();

            foreach (PSPropertyInfo property in element.Properties)
            {
                if (_shouldCreateColumns)
                {
                    ConvertedType firstColumn = AddColumn(property);
                    _columns.Add(property.Name);
                    if (firstColumn.Special)
                    {
                        _specialColumns.Add(property.Name);
                        _specialColumnsType[property.Name] = firstColumn.SpecialType;
                    }
                }

                // PS: try { $propValueLength = $property.value.length } catch { $propValueLength = 0 }
                //     if ($propValueLength -gt 0) { ... }
                object? rawValue;
                bool insertValue;
                try
                {
                    rawValue = property.Value;
                    insertValue = ShouldInsertValue(rawValue);
                }
                catch
                {
                    rawValue = null;
                    insertValue = false;
                }

                if (!insertValue)
                {
                    continue;
                }

                if (ListContains(_specialColumns, property.Name))
                {
                    // PS assigns the special conversion without a local catch.
                    try
                    {
                        datarow[property.Name] = UnwrapForBinder(ConvertSpecialType(rawValue, _specialColumnsType[property.Name]))!;
                    }
                    catch (Exception setException)
                    {
                        string message = string.Format(CultureInfo.CurrentCulture,
                            "Exception setting \"Item\": \"{0}\"", setException.Message);
                        SetValueInvocationException wrapped = new SetValueInvocationException(message, setException);
                        ErrorRecord record = new ErrorRecord(wrapped, "ExceptionWhenSetting", ErrorCategory.NotSpecified, null);
                        if (EnableException.ToBool())
                        {
                            // caller-try: terminate -- -EnableException requests a stop at the failed assignment.
                            ThrowTerminatingError(record); // style-ok: cs-raw-streams preserve the pinned assignment error record
                        }
                        StatementFault.Surface(this, record);
                    }
                }
                else
                {
                    // PS: the length-15 probe joins values whose ToString() is exactly
                    // System.Object[] or System.String[] (both 15 characters) with ", ".
                    object? value;
                    string text = PsToStringCall(rawValue);
                    if (text.Length == 15 && (PsString.Eq(text, "System.Object[]") || PsString.Eq(text, "System.String[]")))
                    {
                        value = JoinOperator(rawValue, ", ");
                    }
                    else
                    {
                        value = rawValue;
                    }

                    try
                    {
                        datarow[property.Name] = UnwrapForBinder(value)!;
                    }
                    catch (Exception setException)
                    {
                        if (!ListContains(_columns, property.Name))
                        {
                            try
                            {
                                ConvertedType newColumn = AddColumn(property);
                                _columns.Add(property.Name);
                                if (newColumn.Special)
                                {
                                    _specialColumns.Add(property.Name);
                                    _specialColumnsType[property.Name] = newColumn.SpecialType;
                                }

                                datarow[property.Name] = UnwrapForBinder(newColumn.Value)!;
                            }
                            catch (Exception addException)
                            {
                                // PS: Stop-Function -Message "Failed to add property ..." -ErrorRecord $_ -Target $object
                                // (no return/continue follows, so processing proceeds with the next property)
                                StopFunction(string.Format("Failed to add property {0} from {1}", property.Name, PsInterpolate(element)),
                                    target: element,
                                    errorRecord: new ErrorRecord(addException, "ConvertTo-DbaDataTable", ErrorCategory.NotSpecified, element),
                                    continueLoop: true);
                            }
                        }
                        else
                        {
                            StopFunction(string.Format("Failed to add property {0} from {1}", property.Name, PsInterpolate(element)),
                                target: element,
                                errorRecord: new ErrorRecord(setException, "ConvertTo-DbaDataTable", ErrorCategory.NotSpecified, element),
                                continueLoop: true);
                        }
                    }
                }
            }

            _datatable.Rows.Add(datarow);
            // PS: after the first non-null object the columns exist; stop creating them.
            if (_shouldCreateColumns)
            {
                _shouldCreateColumns = false;
            }
        }
    }

    protected override void EndProcessing()
    {
        WriteMessage(MessageLevel.InternalComment, "Finished.");
        // PS: , $datatable — emit the DataTable as ONE object (never enumerated into rows).
        WriteObject(_datatable, false);
    }

    /// <summary>
    /// PS: Add-Column — column type from TypeNameOfValue (a ScriptProperty reports its
    /// property-class name instead, which is never accepted and lands as a string column),
    /// Convert-Type for special handling, string default under -Raw.
    /// </summary>
    private ConvertedType AddColumn(PSPropertyInfo property)
    {
        string? typeName;
        try
        {
            typeName = property.TypeNameOfValue;
        }
        catch
        {
            // A throwing value getter is statement-terminating in the PS source (the column
            // still lands as a string); the compiled port skips the error record.
            typeName = null;
        }

        try
        {
            if (property.MemberType == PSMemberTypes.ScriptProperty)
            {
                typeName = property.GetType().FullName;
            }
        }
        catch
        {
            typeName = "System.String";
        }

        object? rawValue;
        try
        {
            rawValue = property.Value;
        }
        catch
        {
            rawValue = null;
        }

        ConvertedType converted = ConvertType(typeName, rawValue);

        DataColumn column = new DataColumn();
        column.ColumnName = property.Name;
        if (!Raw.ToBool())
        {
            // PS: a null resolved type writes a statement fault, then retains the string default.
            try
            {
                column.DataType = Type.GetType(converted.TypeName)!;
            }
            catch (Exception exception) when (exception is not PipelineStoppedException)
            {
                SetValueInvocationException wrapped = new SetValueInvocationException(string.Format(
                    "Exception setting \"DataType\": \"{0}\"", exception.Message), exception);
                ErrorRecord record = new ErrorRecord(wrapped, "ExceptionWhenSetting", ErrorCategory.NotSpecified, null);
                if (EnableException.ToBool())
                {
                    // caller-try: terminate -- -EnableException requests a stop at the failed column type assignment.
                    ThrowTerminatingError(record); // style-ok: cs-raw-streams preserve the pinned DataType assignment record
                }
                StatementFault.Surface(this, record);
            }
        }
        _datatable.Columns.Add(column);
        return converted;
    }

    /// <summary>
    /// PS: Convert-Type — TimeSpan family and Size convert value and type per the user
    /// choice, a non-null dbadatetime[] becomes a joined-string special, anything not in
    /// the accepted list becomes System.String.
    /// </summary>
    private ConvertedType ConvertType(string? typeName, object? value)
    {
        bool special = false;
        string specialType = "";

        if (PsString.In(typeName, "System.TimeSpan", "Dataplat.Dbatools.Utility.DbaTimeSpan", "Dataplat.Dbatools.Utility.DbaTimeSpanPretty"))
        {
            special = true;
            if (PsString.Eq(TimeSpanType, "String"))
            {
                value = PsToStringCall(value);
                typeName = "System.String";
            }
            else
            {
                // PS: $value = $value.$timespantype into an Int64 column (Ticks is a long;
                // the Total* doubles convert at DataRow storage exactly like PS).
                value = PsProperty.Get(value, TimeSpanType);
                typeName = "System.Int64";
            }
            specialType = "Timespan";
        }
        else if (PsString.Eq(typeName, "Dataplat.Dbatools.Utility.Size"))
        {
            special = true;
            if (PsString.Eq(SizeType, "Int64"))
            {
                value = PsProperty.Get(value, "Byte");
                typeName = "System.Int64";
            }
            else if (PsString.Eq(SizeType, "Int32"))
            {
                value = PsProperty.Get(value, "Byte");
                typeName = "System.Int32";
            }
            else if (PsString.Eq(SizeType, "String"))
            {
                value = PsToStringCall(value);
                typeName = "System.String";
            }
            specialType = "Size";
        }
        else if (PsString.Eq(typeName, "Dataplat.Dbatools.Utility.DbaDateTime[]"))
        {
            if (value is not null)
            {
                special = true;
                typeName = "System.String";
                specialType = "String";
            }
        }
        else if (!PsString.In(typeName, AcceptedTypes))
        {
            typeName = "System.String";
        }

        ConvertedType converted = new ConvertedType();
        converted.TypeName = typeName ?? "System.String";
        converted.Value = value;
        converted.Special = special;
        converted.SpecialType = specialType;
        return converted;
    }

    /// <summary>PS: Convert-SpecialType — converts a value for a known special column.</summary>
    private object? ConvertSpecialType(object? value, string specialType)
    {
        switch (specialType)
        {
            case "Size":
                if (PsString.Eq(SizeType, "String"))
                {
                    return PsToStringCall(value);
                }
                return PsProperty.Get(value, "Byte");
            case "Timespan":
                if (PsString.Eq(TimeSpanType, "String"))
                {
                    return PsToStringCall(value);
                }
                return PsProperty.Get(value, TimeSpanType);
            case "DateTime":
                // Unreachable: Convert-Type never records the DateTime special type. Kept for
                // parity with Convert-SpecialType's switch.
                return LanguagePrimitives.ConvertTo(PsProperty.Get(value, "DateTime"), typeof(DateTime), CultureInfo.InvariantCulture);
            case "String":
                // PS: ($Value | ForEach-Object { $_.ToString() }) -Join ', '
                return JoinMethod(value, ", ");
            default:
                return null;
        }
    }

    /// <summary>
    /// PS: $property.value.length -gt 0. The .length member resolves a real (adapted or ETS)
    /// Length property first — strings and arrays — otherwise the engine's scalar intrinsic
    /// yields 1. Windows PowerShell alone has no Length intrinsic on pure property-bag
    /// PSObjects (reads $null, so the value is skipped); PowerShell 7 inserts them.
    /// Lab-proven per-edition divergence; net472 only ever runs under 5.1.
    /// </summary>
    private static bool ShouldInsertValue(object? rawValue)
    {
        if (rawValue is null)
        {
            return false;
        }
        PSObject wrapped = PSObject.AsPSObject(rawValue);
        PSPropertyInfo? lengthProperty = wrapped.Properties["Length"];
        if (lengthProperty is not null)
        {
            object? lengthValue;
            try
            {
                lengthValue = lengthProperty.Value;
            }
            catch
            {
                return false;
            }
            return PsGreaterThanZero(lengthValue);
        }
        return Environment.Version.Major != 4 || wrapped.BaseObject is not PSCustomObject;
    }

    /// <summary>
    /// PS: $length -gt 0 — comparison operators FILTER an enumerable left operand (the result
    /// is the matching elements, truthy when any match); a scalar compares directly with the
    /// left operand's type driving conversion.
    /// </summary>
    private static bool PsGreaterThanZero(object? lengthValue)
    {
        object? unwrapped = lengthValue is PSObject wrapped ? wrapped.BaseObject : lengthValue;
        if (unwrapped is not string && LanguagePrimitives.GetEnumerable(unwrapped) is IEnumerable elements)
        {
            foreach (object? element in elements)
            {
                bool greater;
                try
                {
                    greater = PsOps.Compare(element, 0) > 0;
                }
                catch
                {
                    // A non-comparable element errors per-element in the PS filter and simply
                    // contributes no match.
                    greater = false;
                }
                if (greater)
                {
                    return true;
                }
            }
            return false;
        }
        try
        {
            return PsOps.Compare(unwrapped, 0) > 0;
        }
        catch
        {
            // PS: a failing scalar comparison is statement-terminating inside the length try —
            // the caught path treats the length as 0.
            return false;
        }
    }

    /// <summary>
    /// The PS method binder hands .NET calls the PSObject.Base of each argument: the base
    /// object, except pure property bags which stay the PSObject (so a string column stores
    /// "@{...}" exactly like PS does).
    /// </summary>
    private static object? UnwrapForBinder(object? value)
    {
        if (value is PSObject wrapped)
        {
            return wrapped.BaseObject is PSCustomObject ? wrapped : (object?)wrapped.BaseObject;
        }
        return value;
    }

    /// <summary>
    /// PS .ToString() METHOD-CALL semantics: the binder unwraps the PSObject (pure property
    /// bags stay wrapped) and invokes the instance ToString, with an ETS ToString override
    /// winning like the PS member resolution does. An array therefore renders as
    /// "System.Object[]" — NOT the space-joined display form.
    /// </summary>
    private static string PsToStringCall(object? value)
    {
        if (value is PSObject wrapped)
        {
            PSMemberInfo? etsToString = wrapped.Methods["ToString"];
            // Operator 2026-10-29: only the input value's own ToString at pinned .ToString() sites.
            if (etsToString is PSScriptMethod || etsToString is PSCodeMethod)
            {
                object? overridden = ((PSMethodInfo)etsToString).Invoke();
                return overridden?.ToString() ?? string.Empty;
            }
            object? unwrapped = wrapped.BaseObject is PSCustomObject ? (object)wrapped : wrapped.BaseObject;
            return unwrapped?.ToString() ?? string.Empty;
        }
        return value?.ToString() ?? string.Empty;
    }

    /// <summary>
    /// PS expandable-string semantics ("$object"): the engine's ToStringParser rendering,
    /// which formats property bags as "@{...}" and joins collections — used for the
    /// Stop-Function message interpolation.
    /// </summary>
    private static string PsInterpolate(object? value)
    {
        if (value is null)
        {
            return string.Empty;
        }
        return PSObject.AsPSObject(value).ToString();
    }

    /// <summary>
    /// Shared join core: enumerate the value and stringify each element with the supplied
    /// per-element semantics; a non-enumerable value (including a string) stringifies whole.
    /// </summary>
    private static string JoinCore(object? value, string separator, Func<object?, string> stringify, bool skipNullElements)
    {
        if (value is null)
        {
            return string.Empty;
        }
        object baseValue = value is PSObject wrapped ? wrapped.BaseObject : value;
        if (baseValue is string text)
        {
            return text;
        }
        IEnumerable? enumerable = LanguagePrimitives.GetEnumerable(baseValue);
        if (enumerable is null)
        {
            return stringify(value);
        }
        List<string> parts = new List<string>();
        foreach (object? element in enumerable)
        {
            if (element is null)
            {
                if (!skipNullElements)
                {
                    parts.Add(string.Empty);
                }
                continue;
            }
            parts.Add(stringify(element));
        }
        return string.Join(separator, parts);
    }

    /// <summary>PS: $value -join ", " — the operator renders a null element as an empty string.</summary>
    private static string JoinOperator(object? value, string separator)
    {
        return JoinCore(value, separator, PsInterpolate, skipNullElements: false);
    }

    /// <summary>
    /// PS: ($Value | ForEach-Object { $_.ToString() }) -Join ', ' — method-call per element;
    /// a NULL element's ToString() errors inside ForEach-Object and contributes NO element to
    /// the join (the error record itself is the statement-terminating residual class).
    /// </summary>
    private static string JoinMethod(object? value, string separator)
    {
        return JoinCore(value, separator, PsToStringCall, skipNullElements: true);
    }

    /// <summary>PS: $name -in $list (case-insensitive membership).</summary>
    private static bool ListContains(List<string> list, string name)
    {
        foreach (string entry in list)
        {
            if (PsString.Eq(entry, name))
            {
                return true;
            }
        }
        return false;
    }
}
