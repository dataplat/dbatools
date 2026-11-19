#nullable enable

using System;
using System.Globalization;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>The scalar sibling of PsStringArrayCast: PS [string] converts at BIND time, so
/// an explicit null argument becomes "" before mandatory/validation runs (W1-032 class).
/// Ported verbatim from the core PsCompat during the T8/PsStringCast fleet retrofit - this
/// satellite carried no cast-transform attribute of its own.</summary>
internal sealed class PsStringCastAttribute : ArgumentTransformationAttribute
{
    public override object? Transform(EngineIntrinsics engineIntrinsics, object? inputData)
    {
        return LanguagePrimitives.ConvertTo(inputData, typeof(string), CultureInfo.InvariantCulture);
    }
}
