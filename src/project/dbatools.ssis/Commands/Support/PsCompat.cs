#nullable enable

using System;
using System.Globalization;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>PS [datetime] bind-time cast: script functions convert string arguments with the
/// INVARIANT culture, while the compiled binder uses the CURRENT culture - under de-DE,
/// "01.02.2020" binds Feb 1 compiled vs Jan 2 in the function (lab-proven divergence,
/// W3-060 codex round 1). A null argument keeps the engine's own null-conversion fault,
/// exactly like the script binder's.</summary>
internal sealed class PsDateTimeCastAttribute : ArgumentTransformationAttribute
{
    public override object? Transform(EngineIntrinsics engineIntrinsics, object? inputData)
    {
        return LanguagePrimitives.ConvertTo(inputData, typeof(DateTime), CultureInfo.InvariantCulture);
    }
}
