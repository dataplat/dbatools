using System.Management.Automation;

namespace Dataplat.Dbatools.Commands
{
    /// <summary>Reads the graceful-stop latch belonging to the calling function.</summary>
    [Cmdlet(VerbsDiagnostic.Test, "FunctionInterrupt")]
    [OutputType(typeof(bool))]
    public sealed class TestFunctionInterruptCommand : DbaBaseCmdlet
    {
        /// <summary>Preserves the private helper's parameterless command surface.</summary>
        public override SwitchParameter EnableException
        {
            get { return base.EnableException; }
            set { base.EnableException = value; }
        }

        /// <inheritdoc />
        protected override void EndProcessing()
        {
            // Restrict the lookup to the caller-local latch; ancestor latches belong to other functions.
            PSVariable interruptVariable = SessionState.PSVariable.Get(
                "local:__dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r");
            WriteObject(LanguagePrimitives.IsTrue(interruptVariable == null ? null : interruptVariable.Value));
        }
    }
}
