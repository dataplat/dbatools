using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Computer;

namespace Dataplat.Dbatools.Commands
{
    /// <summary>Returns Windows service return-code messages for internal dbatools callers.</summary>
    [Cmdlet(VerbsCommon.Get, "DbaServiceErrorMessage")]
    [OutputType(typeof(string))]
    public sealed class GetDbaServiceErrorMessageCommand : DbaBaseCmdlet
    {
        /// <summary>The service return code, or zero to return the complete message table.</summary>
        [Parameter(ValueFromPipeline = true, Position = 1)]
        [ServiceErrorNumber]
        public int ErrorNumber { get; set; }

        /// <summary>Retains internal state without exposing a parameter absent from the private function.</summary>
        public override SwitchParameter EnableException
        {
            get { return base.EnableException; }
            set { base.EnableException = value; }
        }

        /// <inheritdoc />
        protected override void EndProcessing()
        {
            if (Interrupted)
                return;

            // The original function has an implicit end block: only the last pipeline value wins.
            foreach (string message in ServiceErrorMessages.Resolve(ErrorNumber))
                WriteObject(message);
        }

        private sealed class ServiceErrorNumberAttribute : ArgumentTransformationAttribute
        {
            public override object Transform(EngineIntrinsics engineIntrinsics, object inputData)
            {
                // Script integer parameters convert null to zero before binding.
                return LanguagePrimitives.ConvertTo(inputData, typeof(int), CultureInfo.InvariantCulture);
            }
        }
    }
}
