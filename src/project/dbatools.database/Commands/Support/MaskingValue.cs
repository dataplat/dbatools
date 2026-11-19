#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Text.RegularExpressions;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Result shape of Convert-DbaMaskingValue: one entry per input item. On the normal path
/// NewValue/ErrorMessage are EMPTY STRINGS when unset (the PS source declares
/// [string]$newValue = $null, which IS ""); only the begin-block NULL object carries a
/// true null ErrorMessage - callers discriminate errors with PS truthiness, so "" and
/// null are equally falsy there, but the shape is pinned to the original.
/// </summary>
public sealed class MaskingValue
{
    /// <summary>The raw input item, except null/PS-falsy items which become the literal string "$null".</summary>
    public object? OriginalValue;
    public string? NewValue;
    /// <summary>The RAW DataType argument (never lowercased; "" when the caller passed none).</summary>
    public string? DataType;
    public string? ErrorMessage;
}

/// <summary>
/// Port of private/functions/Convert-DbaMaskingValue.ps1 (TB-012): renders a masking value
/// in T-SQL literal form. All five call sites live in Invoke-DbaDbDataMasking (database
/// family, hence this satellite per the caller-list ownership rule; the tracker Module
/// column said dbatools.library - discrepancy recorded in Evidence) and every site passes
/// -EnableException, so the begin-block Stop-Function gates are ported as throws the
/// compiled caller catches (Stop-Function -Continue under EnableException still
/// terminates). Pure string logic - no SMO, fully offline-testable.
///
/// PS semantics preserved (ground-truthed on 5.1 + 7.6, probe 2026-07-16):
/// - The value gate uses PS truthiness on the WHOLE [object[]]: a falsy scalar (0, $false,
///   "", $null) aborts with "Please enter a value" before any item is examined; with
///   Nullable BOTH gates are skipped, including the data-type gate.
/// - A PS-falsy ITEM (0, $false, "" inside a multi-element array) folds to
///   OriginalValue "$null" (literal) / NewValue "NULL" - so bit 0 and bool $false can
///   never emit "0"; only the strings "0"/"false" can. Preserved bug.
/// - The source's elseif ($item -eq '') branch is DEAD CODE: "" is falsy and is captured
///   by the null branch first (probed - "" emits "$null"/"NULL" even without Nullable).
///   It is not reproduced; this note is the record of that decision.
/// - The numeric regex \b\d+([\.,]\d+)? is UNANCHORED: any digit-bearing string passes
///   through RAW and unquoted ("1;DROP" survives verbatim). Preserved verbatim - the
///   value reaches the caller's dynamic SQL unescaped; flagged to the masking row.
/// - The switch's missing breaks are safe because no reachable datatype string matches
///   two clauses (checked: no clause-1/2 name contains "int" or collides with the
///   equality clauses), so the if/else chain here is output-equivalent.
/// - "$item" interpolation and -match/-eq item stringification ride
///   LanguagePrimitives.ConvertTo (culture-invariant), and [datetime]$item is the same
///   engine conversion; the two current-culture surfaces in the source are preserved
///   AS current-culture: the time branch's ToString("HH:mm:ss.fffffff") (no invariant
///   argument - the ":" glyph follows the culture's time separator) and the default
///   branch's .ToString() method call.
/// - Documented divergence (TB-010 precedent): the datatype switch lowers with
///   ToLowerInvariant where the source's .ToLower() is current-culture (tr-TR dotless-i
///   would send e.g. BIT to the default branch there); the invariant form is intended.
/// - A datetime-family item that passes the format regex but fails the [datetime]
///   conversion throws out of the helper in PS (statement-terminating, taken by the
///   caller's catch); the port lets the same conversion exception propagate.
/// - PS -eq semantics in the bit branch are modeled with LanguagePrimitives.Compare
///   (RHS converts to the LHS type; conversion failure is quietly FALSE, so integer 5
///   lands on the BIT/BOOL error message rather than throwing).
/// </summary>
public static class MaskingValueConverter
{
    private static readonly Regex BitPattern = new Regex("^[01]$", RegexOptions.IgnoreCase);
    private static readonly Regex NumericPattern = new Regex(@"\b\d+([\.,]\d+)?", RegexOptions.IgnoreCase);
    private static readonly Regex IsoDatePattern = new Regex(@"(\d{4})-(\d{2})-(\d{2})", RegexOptions.IgnoreCase);
    private static readonly Regex UsDatePattern = new Regex(@"(\d{2})/(\d{2})/(\d{4})", RegexOptions.IgnoreCase);
    private static readonly Regex TimePattern = new Regex(@"(\d{2}):(\d{2}):(\d{2})", RegexOptions.IgnoreCase);

    /// <summary>The full helper: begin-block gates + per-item conversion.</summary>
    public static List<MaskingValue> Convert(object?[]? value, string? dataType, bool nullable)
    {
        List<MaskingValue> results = new List<MaskingValue>();
        string rawDataType = dataType ?? string.Empty;

        // begin: Stop-Function gates (EnableException semantics - every caller passes it).
        if (!nullable && !LanguagePrimitives.IsTrue(value))
            throw new InvalidOperationException("Please enter a value");
        if (!nullable && !LanguagePrimitives.IsTrue(rawDataType))
            throw new InvalidOperationException("Please enter a data type");

        // begin: $Value.Count -eq 0 -and $Nullable ($null.Count is 0 in PS) - the one
        // object whose ErrorMessage is a true null.
        if ((value == null || value.Length == 0) && nullable)
        {
            results.Add(new MaskingValue
            {
                OriginalValue = "$null",
                NewValue = "NULL",
                DataType = rawDataType,
                ErrorMessage = null
            });
        }

        if (value == null)
            return results;

        foreach (object? item in value)
        {
            object? originalValue = item;
            string newValue = string.Empty;
            string errorMessage = string.Empty;

            if (item == null || !LanguagePrimitives.IsTrue(item))
            {
                originalValue = "$null";
                newValue = "NULL";
            }
            else
            {
                string itemText = PsString(item);
                string loweredType = rawDataType.ToLowerInvariant();

                if (loweredType == "bit" || loweredType == "bool")
                {
                    if (BitPattern.IsMatch(itemText))
                        newValue = itemText;
                    else if (PsEq(item, "true"))
                        newValue = "1";
                    else if (PsEq(item, "false"))
                        newValue = "0";
                    else
                        errorMessage = $"Value '{itemText}' is not valid BIT or BOOL";
                }
                else if (loweredType.Contains("int") || loweredType == "decimal" || loweredType == "numeric" || loweredType == "float" || loweredType == "money" || loweredType == "smallmoney" || loweredType == "real")
                {
                    if (NumericPattern.IsMatch(itemText))
                        newValue = itemText;
                    else
                        errorMessage = $"Value '{itemText}' is not valid integer/decimal format";
                }
                else if (loweredType == "uniqueidentifier")
                {
                    // No quote escaping in the source - preserved.
                    newValue = "'" + itemText + "'";
                }
                else if (loweredType == "datetime")
                {
                    newValue = ConvertDateFamily(item, itemText, "yyyy-MM-dd HH:mm:ss.fff", ref errorMessage);
                }
                else if (loweredType == "datetime2")
                {
                    newValue = ConvertDateFamily(item, itemText, "yyyy-MM-dd HH:mm:ss.fffffff", ref errorMessage);
                }
                else if (loweredType == "date")
                {
                    newValue = ConvertDateFamily(item, itemText, "yyyy-MM-dd", ref errorMessage);
                }
                else if (loweredType == "smalldatetime")
                {
                    // Source uses -like with no wildcards: plain case-insensitive equality.
                    newValue = ConvertDateFamily(item, itemText, "yyyy-MM-dd HH:mm:ss", ref errorMessage);
                }
                else if (loweredType == "time")
                {
                    if (TimePattern.IsMatch(itemText))
                    {
                        // Source line 168 omits the invariant culture here - the one
                        // date-family branch whose separators follow the current culture.
                        DateTime parsed = LanguagePrimitives.ConvertTo<DateTime>(item);
                        newValue = "'" + parsed.ToString("HH:mm:ss.fffffff") + "'";
                    }
                    else
                    {
                        errorMessage = $"Value '{itemText}' is not valid TIME format (HH:mm:ss)";
                    }
                }
                else if (loweredType == "xml")
                {
                    // Source: "nothing, unsure how i'll handle this" - NewValue stays ""
                    // with no error. Preserved silently-empty behavior.
                }
                else
                {
                    // Method-call ToString: current culture, unlike the interpolations.
                    newValue = "'" + (item.ToString() ?? string.Empty).Replace("'", "''") + "'";
                }
            }

            results.Add(new MaskingValue
            {
                OriginalValue = originalValue,
                NewValue = newValue,
                DataType = rawDataType,
                ErrorMessage = errorMessage
            });
        }

        return results;
    }

    private static string ConvertDateFamily(object item, string itemText, string format, ref string errorMessage)
    {
        if (IsoDatePattern.IsMatch(itemText) || UsDatePattern.IsMatch(itemText))
        {
            DateTime parsed = LanguagePrimitives.ConvertTo<DateTime>(item);
            return "'" + parsed.ToString(format, CultureInfo.InvariantCulture) + "'";
        }
        errorMessage = $"Value '{itemText}' is not valid DATE or DATETIME format (yyyy-MM-dd)";
        return string.Empty;
    }

    /// <summary>"$item" interpolation / -match LHS parity: the engine string conversion.</summary>
    private static string PsString(object item)
    {
        return LanguagePrimitives.ConvertTo<string>(item) ?? string.Empty;
    }

    /// <summary>PS -eq parity for the bit branch: RHS converts to the LHS type, and a
    /// failed conversion is quietly not-equal (integer 5 -eq "true" is false, not a throw).</summary>
    private static bool PsEq(object item, string literal)
    {
        try
        {
            return LanguagePrimitives.Compare(item, literal, ignoreCase: true) == 0;
        }
        catch
        {
            return false;
        }
    }
}
