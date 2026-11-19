using System.Management.Automation;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands
{
    /// <summary>Returns the bounded inner exception message for internal dbatools callers.</summary>
    [Cmdlet(VerbsCommon.Get, "ErrorMessage")]
    public sealed class GetErrorMessageCommand : DbaBaseCmdlet
    {
        /// <summary>The error record whose exception message is returned.</summary>
        [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
        public ErrorRecord Record { get; set; }

        /// <summary>Retains internal state without exposing a parameter absent from the private function.</summary>
        public override SwitchParameter EnableException
        {
            get { return base.EnableException; }
            set { base.EnableException = value; }
        }

        /// <inheritdoc />
        protected override void ProcessRecord()
        {
            if (Interrupted)
                return;

            WriteObject(MessageService.GetErrorMessage(Record));
        }
    }
}
