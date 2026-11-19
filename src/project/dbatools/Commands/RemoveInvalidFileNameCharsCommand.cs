using System;
using System.IO;
using System.Management.Automation;
using System.Text.RegularExpressions;

namespace Dataplat.Dbatools.Commands
{
    /// <summary>Removes invalid filename characters for internal dbatools callers.</summary>
    [Cmdlet(VerbsCommon.Remove, "InvalidFileNameChars")]
    public sealed class RemoveInvalidFileNameCharsCommand : DbaBaseCmdlet
    {
        /// <summary>The filename text to filter.</summary>
        [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true, ValueFromPipelineByPropertyName = true)]
        public string Name { get; set; }

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

            // The private function has an implicit end block, so only the last pipeline value is returned.
            string invalidCharacters = new string(Path.GetInvalidFileNameChars());
            string pattern = "[" + Regex.Escape(invalidCharacters) + "]";
            WriteObject(Regex.Replace(Name, pattern, String.Empty, RegexOptions.IgnoreCase));
        }
    }
}
