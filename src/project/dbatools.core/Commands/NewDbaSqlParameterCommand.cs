#nullable enable

using System;
using System.Data;
using System.Data.SqlTypes;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a Microsoft.Data.SqlClient.SqlParameter with bound-parameter-driven property
/// assignment. Port of public/New-DbaSqlParameter.ps1 (W1-030). Every Test-Bound property
/// set converts through LanguagePrimitives like the PS assignment binder (string params
/// feeding int/byte/enum properties: Offset, Precision, Scale, the enum sets), so a bad
/// value faults with the same deepest conversion message the function's catch handed
/// Stop-Function "Failure". The Value/SqlValue objects assign through PSObject.Base - the
/// PS assignment binder unwraps the pipeline transit wrapper (pure property bags stay
/// PSObject), and an object-typed compiled parameter RECEIVES that wrapper, which
/// Microsoft.Data.SqlClient's TVP path rejects at Fill time ("Failed to convert parameter
/// value from a PSObject to a IEnumerable`1" - lab-proven 2026-07-12 via Invoke-DbaQuery's
/// structured-parameter test; PS-side probes cannot observe the wrapper because the method
/// binder unwraps at every boundary). Falsy CLR values still bind (#9542) - Base preserves
/// them. Positions 0-15 pin the PS implicit positional binding
/// (non-switch parameters numbered consecutively; switches never positional).
/// Surface pinned by migration/baselines/New-DbaSqlParameter.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaSqlParameter")]
public sealed class NewDbaSqlParameterCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    [Parameter(Position = 0)]
    [PsStringCast]
    [ValidateSet("None", "IgnoreCase", "IgnoreNonSpace", "IgnoreKanaType", "IgnoreWidth", "BinarySort2", "BinarySort")]
    public string? CompareInfo { get; set; }

    [Parameter(Position = 1)]
    [PsStringCast]
    [ValidateSet("AnsiString", "Binary", "Byte", "Boolean", "Currency", "Date", "DateTime", "Decimal", "Double", "Guid", "Int16", "Int32", "Int64", "Object", "SByte", "Single", "String", "Time", "UInt16", "UInt32", "UInt64", "VarNumeric", "AnsiStringFixedLength", "StringFixedLength", "Xml", "DateTime2", "DateTimeOffset")]
    public string? DbType { get; set; }

    [Parameter(Position = 2)]
    [PsStringCast]
    [ValidateSet("Input", "Output", "InputOutput", "ReturnValue")]
    public string? Direction { get; set; }

    [Parameter]
    public SwitchParameter ForceColumnEncryption { get; set; }

    [Parameter]
    public SwitchParameter IsNullable { get; set; }

    [Parameter(Position = 3)]
    public int LocaleId { get; set; }

    [Parameter(Position = 4)]
    public string? Offset { get; set; }

    [Parameter(Position = 5)]
    [Alias("Name")]
    public string? ParameterName { get; set; }

    [Parameter(Position = 6)]
    public string? Precision { get; set; }

    [Parameter(Position = 7)]
    public string? Scale { get; set; }

    [Parameter(Position = 8)]
    public int Size { get; set; }

    [Parameter(Position = 9)]
    public string? SourceColumn { get; set; }

    [Parameter]
    public SwitchParameter SourceColumnNullMapping { get; set; }

    [Parameter(Position = 10)]
    [PsStringCast]
    [ValidateSet("Original", "Current", "Proposed", "Default")]
    public string? SourceVersion { get; set; }

    [Parameter(Position = 11)]
    [PsStringCast]
    [ValidateSet("BigInt", "Binary", "Bit", "Char", "DateTime", "Decimal", "Float", "Image", "Int", "Money", "NChar", "NText", "NVarChar", "Real", "UniqueIdentifier", "SmallDateTime", "SmallInt", "SmallMoney", "Text", "Timestamp", "TinyInt", "VarBinary", "VarChar", "Variant", "Xml", "Udt", "Structured", "Date", "Time", "DateTime2", "DateTimeOffset")]
    public string? SqlDbType { get; set; }

    [Parameter(Position = 12)]
    public object? SqlValue { get; set; }

    [Parameter(Position = 13)]
    public string? TypeName { get; set; }

    [Parameter(Position = 14)]
    public string? UdtTypeName { get; set; }

    [Parameter(Position = 15)]
    public object? Value { get; set; }

    protected override void EndProcessing()
    {
        Microsoft.Data.SqlClient.SqlParameter param = new();

        try
        {
            if (TestBound("CompareInfo"))
                param.CompareInfo = (SqlCompareOptions)LanguagePrimitives.ConvertTo(CompareInfo, typeof(SqlCompareOptions), null);

            if (TestBound("DbType"))
                param.DbType = (System.Data.DbType)LanguagePrimitives.ConvertTo(DbType, typeof(System.Data.DbType), null);

            if (TestBound("Direction"))
                param.Direction = (ParameterDirection)LanguagePrimitives.ConvertTo(Direction, typeof(ParameterDirection), null);

            if (TestBound("ForceColumnEncryption"))
                param.ForceColumnEncryption = ForceColumnEncryption.ToBool();

            if (TestBound("IsNullable"))
                param.IsNullable = IsNullable.ToBool();

            if (TestBound("LocaleId"))
                param.LocaleId = LocaleId;

            if (TestBound("Offset"))
                param.Offset = LanguagePrimitives.ConvertTo<int>(Offset);

            if (TestBound("ParameterName"))
                param.ParameterName = ParameterName;

            if (TestBound("Precision"))
                param.Precision = LanguagePrimitives.ConvertTo<byte>(Precision);

            if (TestBound("Scale"))
                param.Scale = LanguagePrimitives.ConvertTo<byte>(Scale);

            if (TestBound("Size"))
                param.Size = Size;

            if (TestBound("SourceColumn"))
                param.SourceColumn = SourceColumn;

            if (TestBound("SourceColumnNullMapping"))
                param.SourceColumnNullMapping = SourceColumnNullMapping.ToBool();

            if (TestBound("SourceVersion"))
                param.SourceVersion = (DataRowVersion)LanguagePrimitives.ConvertTo(SourceVersion, typeof(DataRowVersion), null);

            if (TestBound("SqlDbType"))
                param.SqlDbType = (System.Data.SqlDbType)LanguagePrimitives.ConvertTo(SqlDbType, typeof(System.Data.SqlDbType), null);

            if (TestBound("SqlValue"))
                param.SqlValue = PsAssignment.Unwrap(SqlValue);

            if (TestBound("TypeName"))
                param.TypeName = TypeName;

            if (TestBound("UdtTypeName"))
                param.UdtTypeName = UdtTypeName;

            if (TestBound("Value"))
                param.Value = PsAssignment.Unwrap(Value);

            WriteObject(param);
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            // PS: catch { Stop-Function -Message "Failure" -ErrorRecord $_; return }
            StopFunction("Failure", errorRecord: ToCaughtRecord(ex));
            return;
        }
    }

    /// <summary>PS: catch { $_ } - a hand-built RuntimeException's lazy record drops the
    /// inner chain (ParentContainsErrorRecordException), so that shape rebuilds.</summary>
    private static ErrorRecord ToCaughtRecord(Exception ex)
    {
        if (ex is RuntimeException runtime && runtime.ErrorRecord is not null &&
            runtime.ErrorRecord.Exception is not ParentContainsErrorRecordException)
        {
            return runtime.ErrorRecord;
        }
        return new ErrorRecord(ex, "New-DbaSqlParameter", ErrorCategory.NotSpecified, null);
    }
}
