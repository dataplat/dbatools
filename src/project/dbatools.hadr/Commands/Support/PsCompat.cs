#nullable enable

using System;
using System.Globalization;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>PS [datetime] bind-time cast: script functions convert string arguments with the
/// INVARIANT culture, while the compiled binder uses the CURRENT culture - under de-DE,
/// "01.02.2020" binds Feb 1 compiled vs Jan 2 in the function (a lab-proven divergence).
/// A null argument keeps the engine's own null-conversion fault, exactly like the script
/// binder's.</summary>
internal sealed class PsDateTimeCastAttribute : ArgumentTransformationAttribute
{
    public override object? Transform(EngineIntrinsics engineIntrinsics, object? inputData)
    {
        return LanguagePrimitives.ConvertTo(inputData, typeof(DateTime), CultureInfo.InvariantCulture);
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

/// <summary>Reproduces the PS [string[]] bind-time cast for compiled parameters: script
/// functions convert the argument BEFORE mandatory validation, so a null ELEMENT becomes
/// "" and the mandatory rejection reports "empty string" exactly like the function (the
/// compiled binder would otherwise validate the raw null and report "null" - a lab-proven
/// divergence). CONSERVATIVE ON PURPOSE: it converts ONLY an array carrying a null
/// element - the exact divergence input - and passes every other value through untouched.
/// A blanket ConvertTo also "succeeded" for a piped PSCustomObject during the pipeline
/// BY-VALUE attempt, stringifying the whole object and silently preempting the
/// ByPropertyName binding the script function performs.</summary>
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
