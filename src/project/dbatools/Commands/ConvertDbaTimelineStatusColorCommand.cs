using System;
using System.Globalization;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands
{
    /// <summary>Maps a job status to the private timeline helper's color.</summary>
    [Cmdlet(VerbsData.Convert, "DbaTimelineStatusColor")]
    public sealed class ConvertDbaTimelineStatusColorCommand : DbaBaseCmdlet
    {
        /// <summary>The literal job status.</summary>
        [Parameter(Mandatory = true, Position = 0)]
        [TimelineStatusArgument]
        public string Status { get; set; }

        public override SwitchParameter EnableException { get; set; }

        protected override void EndProcessing()
        {
            if (Interrupted)
                return;

            string color = "#FF00CC";
            if (LanguagePrimitives.Equals(Status, "Failed", true, CultureInfo.InvariantCulture))
                color = "#FF3D3D";
            else if (LanguagePrimitives.Equals(Status, "Succeeded", true, CultureInfo.InvariantCulture))
                color = "#36B300";
            else if (LanguagePrimitives.Equals(Status, "Retry", true, CultureInfo.InvariantCulture))
                color = "#FFFF00";
            else if (LanguagePrimitives.Equals(Status, "Canceled", true, CultureInfo.InvariantCulture))
                color = "#C2C2C2";
            else if (LanguagePrimitives.Equals(Status, "In Progress", true, CultureInfo.InvariantCulture))
                color = "#00CCFF";
            WriteObject(color);
        }
    }

    // Match the script string binder's measured null and array rejection paths.
    internal sealed class TimelineStatusArgumentAttribute : ArgumentTransformationAttribute
    {
        public override object Transform(EngineIntrinsics engineIntrinsics, object inputData)
        {
            PSObject wrapped = inputData as PSObject;
            object value = wrapped == null ? inputData : wrapped.BaseObject;
            if (value == null)
                return String.Empty;
            if (value is Array)
                throw new ArgumentTransformationMetadataException("Cannot convert value to type System.String.");
            return inputData;
        }
    }
}
