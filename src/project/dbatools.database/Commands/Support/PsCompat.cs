#nullable enable

using System;
using System.Collections;
using System.Globalization;
using System.Management.Automation;
using System.Numerics;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// PSObject dynamic property access with PS non-strict semantics: a missing property reads
/// as null, DataRow columns / class fields / ETS note properties are all reachable the same
/// way the PS dot operator reached them.
/// </summary>
internal static class PsProperty
{
    /// <summary>Reads a property (adapted, class, or note) off any object; null when absent.</summary>
    internal static object? Get(object? item, string name)
    {
        if (item is null)
            return null;
        PSObject wrapped = PSObject.AsPSObject(item);
        PSPropertyInfo? property = wrapped.Properties[name];
        if (property is null)
            return null;
        object? value;
        try { value = property.Value; }
        catch { return null; }
        // Deserialized complex values (CliXml property bags, e.g. BigInteger LSNs) keep the
        // PSObject wrapper: its overriding ToString survives deserialization while the bare
        // PSCustomObject base renders empty. Everything else unwraps like the PS dot operator.
        if (value is PSObject psValue && psValue.BaseObject is not PSCustomObject)
            value = psValue.BaseObject;
        if (value is DBNull)
            return null;
        return value;
    }

    /// <summary>Whether the object exposes the named property ("X" -in $obj.PSObject.Properties.Name).</summary>
    internal static bool Has(object? item, string name)
    {
        if (item is null)
            return false;
        return PSObject.AsPSObject(item).Properties[name] is not null;
    }

    /// <summary>Sets an existing property's value (class field, note property, or DataRow column).</summary>
    internal static void Set(object item, string name, object? value)
    {
        PSObject wrapped = PSObject.AsPSObject(item);
        PSPropertyInfo? property = wrapped.Properties[name];
        if (property is not null)
            property.Value = value;
    }

    /// <summary>Add-Member -MemberType NoteProperty parity (only when not already present).</summary>
    internal static void AddNote(object item, string name, object? value)
    {
        PSObject wrapped = PSObject.AsPSObject(item);
        if (wrapped.Properties[name] is null)
            wrapped.Properties.Add(new PSNoteProperty(name, value));
    }
}

/// <summary>LSN readings, replicating the PS [BigInt]$value.ToString() cast chain.</summary>
internal static class PsLsn
{
    /// <summary>Converts an LSN-carrying value (decimal, BigInteger, string, DBNull, or a
    /// deserialized BigInteger property bag) to BigInteger, like [BigInt]$value.ToString().</summary>
    internal static BigInteger ToBigInt(object? value)
    {
        if (value is PSObject psValue && psValue.BaseObject is not PSCustomObject)
            value = psValue.BaseObject;
        if (value is null || value is DBNull)
            return BigInteger.Zero;
        if (value is BigInteger big)
            return big;
        // LanguagePrimitives honors the deserialized ToString override; Convert.ToString on
        // the bare property bag would render empty.
        string text = (string)LanguagePrimitives.ConvertTo(value, typeof(string), CultureInfo.InvariantCulture);
        if (text.Length == 0)
            return BigInteger.Zero;
        // Decimal-typed LSNs can stringify with a trailing ".0"-less integral form already;
        // BigInteger.Parse on the integral text matches [BigInt]"..." exactly.
        return BigInteger.Parse(text, NumberStyles.Integer, CultureInfo.InvariantCulture);
    }
}

/// <summary>PS string-rendering helpers for message parity.</summary>
internal static class PsBool
{
    /// <summary>PS renders booleans as True/False inside expandable strings.</summary>
    internal static string Text(bool value)
    {
        return value ? "True" : "False";
    }
}

/// <summary>PS comparison-operator parity (case-insensitive -eq / -in).</summary>
internal static class PsString
{
    /// <summary>The PS -eq operator for strings: case-insensitive, invariant culture.
    /// Canonically equivalent composed/decomposed strings compare EQUAL on both editions;
    /// an ordinal comparison would report them as different.</summary>
    internal static bool Eq(string? left, string? right)
    {
        return string.Equals(left, right, StringComparison.InvariantCultureIgnoreCase);
    }

    /// <summary>The PS -in operator over a literal string list: case-insensitive, invariant.</summary>
    internal static bool In(string? value, params string[] candidates)
    {
        foreach (string candidate in candidates)
        {
            if (string.Equals(value, candidate, StringComparison.InvariantCultureIgnoreCase))
                return true;
        }
        return false;
    }
}

/// <summary>
/// PS @{} hashtable-literal construction parity: the engine pre-sizes the table with the
/// literal's entry count, and that capacity changes the bucket enumeration order on
/// Windows PowerShell 5.1. The comparer is EDITION-SPLIT - 5.1 literals hash
/// culture-insensitively while 7 keys ordinally, so a composed/decomposed e-acute pair
/// collides on 5.1 and stays distinct on 7.
/// </summary>
internal static class PsHashtable
{
    /// <summary>Builds a hashtable shaped like a PS @{} literal with the given entry count.</summary>
    internal static Hashtable Literal(int capacity)
    {
#if NETFRAMEWORK
        return new Hashtable(capacity, StringComparer.CurrentCultureIgnoreCase);
#else
        return new Hashtable(capacity, StringComparer.OrdinalIgnoreCase);
#endif
    }
}

/// <summary>
/// PS operator semantics over arbitrary values, backed by the engine's own
/// LanguagePrimitives so type-coercion rules (left operand wins, case-insensitive strings,
/// null conversion) match the retired PS source exactly.
/// </summary>
internal static class PsOps
{
    /// <summary>The PS -eq operator (case-insensitive, lhs-type-driven conversion).</summary>
    internal static bool Eq(object? left, object? right)
    {
        return LanguagePrimitives.Equals(Unwrap(left), Unwrap(right), true);
    }

    /// <summary>The PS comparison engine (-lt/-le/-gt/-ge): negative, zero, positive.</summary>
    internal static int Compare(object? left, object? right)
    {
        return LanguagePrimitives.Compare(Unwrap(left), Unwrap(right), true);
    }

    /// <summary>
    /// The PS -in operator over any collection. $value -in $collection is evaluated as
    /// "any element -eq $value" with the ELEMENT as the left operand — so a single-element
    /// array value coerces to the element's type and can match.
    /// </summary>
    internal static bool In(object? value, object? collection)
    {
        if (Unwrap(collection) is not System.Collections.IEnumerable items || collection is string)
        {
            return Eq(collection, value);
        }
        foreach (object? item in items)
        {
            if (Eq(item, value))
                return true;
        }
        return false;
    }

    /// <summary>PS truthiness (if ($x) { ... }).</summary>
    internal static bool IsTrue(object? value)
    {
        return LanguagePrimitives.IsTrue(value);
    }

    private static object? Unwrap(object? value)
    {
        if (value is PSObject psValue)
            return psValue.BaseObject;
        return value;
    }
}

/// <summary>Reproduces the PS [string[]] bind-time cast for compiled parameters: script
/// functions convert the argument BEFORE mandatory validation, so a null ELEMENT becomes
/// "" and the mandatory rejection reports "empty string" exactly like the function. The
/// compiled binder would otherwise validate the raw null and report "null".
/// CONSERVATIVE ON PURPOSE: it converts ONLY an array carrying a null element - the exact
/// divergence input - and passes every other value through untouched. A blanket ConvertTo
/// also "succeeds" for a piped PSCustomObject during the pipeline BY-VALUE binding attempt,
/// stringifying the whole object and silently preempting the ByPropertyName binding the
/// script function performs.</summary>
internal sealed class PsStringArrayCastAttribute : ArgumentTransformationAttribute
{
    public override object? Transform(EngineIntrinsics engineIntrinsics, object? inputData)
    {
        if (inputData is null)
            return null;
        object bare = inputData is PSObject pso ? pso.BaseObject : inputData;
        if (bare is not System.Collections.IList list)
            return inputData;
        foreach (object? element in list)
        {
            object? bareElement = element is PSObject p ? p.BaseObject : element;
            if (bareElement is null)
                return LanguagePrimitives.ConvertTo(inputData, typeof(string[]), CultureInfo.InvariantCulture);
        }
        return inputData;
    }
}

/// <summary>The int-array sibling of PsStringArrayCast: the script [int[]] cast converts a
/// null ELEMENT to 0 BEFORE validation attributes run, so ValidateRange rejects with the
/// RANGE message where the compiled binder would report null. CONSERVATIVE like the string
/// sibling: converts ONLY an array carrying a null element and passes every other value
/// through so pipeline BY-VALUE binding attempts are never preempted.</summary>
internal sealed class PsIntArrayCastAttribute : ArgumentTransformationAttribute
{
    public override object? Transform(EngineIntrinsics engineIntrinsics, object? inputData)
    {
        if (inputData is null)
            return null;
        object bare = inputData is PSObject pso ? pso.BaseObject : inputData;
        if (bare is not System.Collections.IList list)
            return inputData;
        foreach (object? element in list)
        {
            object? bareElement = element is PSObject p ? p.BaseObject : element;
            if (bareElement is null)
                return LanguagePrimitives.ConvertTo(inputData, typeof(int[]), CultureInfo.InvariantCulture);
        }
        return inputData;
    }
}

/// <summary>The scalar sibling of PsStringArrayCast: PS [string] converts at BIND time, so
/// an explicit null argument becomes "" before mandatory/validation runs.</summary>
internal sealed class PsStringCastAttribute : ArgumentTransformationAttribute
{
    public override object? Transform(EngineIntrinsics engineIntrinsics, object? inputData)
    {
        return LanguagePrimitives.ConvertTo(inputData, typeof(string), CultureInfo.InvariantCulture);
    }
}

/// <summary>PS [int] bind-time cast. A script [int] parameter converts an explicit null
/// argument to 0; the compiled binder instead FAILS to bind it ("Cannot convert null to
/// type System.Int32"), so this transform is required for parity on any int parameter that
/// can receive an explicit null - not only ones carrying validation attributes. Where a
/// validation attribute is present, the conversion also has to happen before it runs, so
/// [ValidateNotNull()][int] accepts -Param $null as 0 exactly like the function.</summary>
internal sealed class PsIntCastAttribute : ArgumentTransformationAttribute
{
    public override object? Transform(EngineIntrinsics engineIntrinsics, object? inputData)
    {
        return LanguagePrimitives.ConvertTo(inputData, typeof(int), CultureInfo.InvariantCulture);
    }
}

/// <summary>PS [datetime] bind-time cast: script functions convert string arguments with the
/// INVARIANT culture, while the compiled binder uses the CURRENT culture - under de-DE,
/// "01.02.2020" binds Feb 1 compiled vs Jan 2 in the function. A null argument keeps the
/// engine's own null-conversion fault, exactly like the script binder's.</summary>
internal sealed class PsDateTimeCastAttribute : ArgumentTransformationAttribute
{
    public override object? Transform(EngineIntrinsics engineIntrinsics, object? inputData)
    {
        return LanguagePrimitives.ConvertTo(inputData, typeof(DateTime), CultureInfo.InvariantCulture);
    }
}

/// <summary>The PS property-assignment binder's argument conversion.</summary>
internal static class PsAssignment
{
    /// <summary>Unwraps the pipeline-transit PSObject wrapper to its base object, EXCEPT
    /// pure property bags, which stay PSObject (their PSCustomObject base is an empty
    /// sentinel) - exactly what a PS `$store.Property = $value` assignment binds. Use for
    /// any bound object-typed compiled parameter assigned into a .NET store consumed by
    /// pure .NET code: the compiled binder KEEPS the wrapper, PS-side probes cannot see it
    /// (the method binder unwraps at every boundary), and consumers like
    /// Microsoft.Data.SqlClient's TVP binding reject it.</summary>
    internal static object? Unwrap(object? value)
    {
        if (value is PSObject psValue && psValue.BaseObject is not PSCustomObject)
            return psValue.BaseObject;
        return value;
    }
}
