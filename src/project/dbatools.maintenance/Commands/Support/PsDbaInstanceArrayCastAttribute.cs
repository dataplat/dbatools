#nullable enable

using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>Reproduces an advanced function's typed-array conversion before validation.</summary>
internal sealed class PsDbaInstanceArrayCastAttribute : ArgumentTransformationAttribute
{
    public override object? Transform(EngineIntrinsics engineIntrinsics, object? inputData)
    {
        if (inputData is null)
            return null;

        try
        {
            return LanguagePrimitives.ConvertTo(inputData, typeof(DbaInstanceParameter[]), CultureInfo.InvariantCulture);
        }
        catch (PSInvalidCastException ex)
        {
            throw new ArgumentTransformationMetadataException(ex.Message, ex);
        }
    }
}
