using System.Management.Automation;
using Dataplat.Dbatools.Connection;

namespace Dataplat.Dbatools.Commands
{
    /// <summary>Masks passwords in the private connection string helper.</summary>
    [Cmdlet(VerbsCommon.Hide, "ConnectionString")]
    public sealed class HideConnectionStringCommand : DbaBaseCmdlet
    {
        /// <summary>The connection string to normalize and mask.</summary>
        [Parameter(Position = 0)]
        [TimelineStatusArgument]
        public string ConnectionString { get; set; } = "";

        public override SwitchParameter EnableException { get; set; }

        protected override void EndProcessing()
        {
            if (Interrupted)
                return;

            WriteObject(ConnectionService.HideConnectionString(ConnectionString));
        }
    }
}
