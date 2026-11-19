using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands
{
    /// <summary>Returns pinned SQL Server configuration defaults for internal dbatools callers.</summary>
    [Cmdlet(VerbsCommon.Get, "SqlDefaultSpConfigure")]
    public sealed class GetSqlDefaultSpConfigureCommand : DbaBaseCmdlet
    {
        /// <summary>The SQL major version or collection of versions to look up.</summary>
        [Parameter(Mandatory = true, Position = 0)]
        [ValidateNotNullOrEmpty]
        [Alias("Version")]
        public object SqlVersion { get; set; }

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

            IEnumerator versions = LanguagePrimitives.GetEnumerator(SqlVersion);
            if (versions == null)
            {
                EmitDefaults(SqlVersion);
                return;
            }

            try
            {
                while (!Interrupted && versions.MoveNext())
                    EmitDefaults(versions.Current);
            }
            finally
            {
                IDisposable disposable = versions as IDisposable;
                if (disposable != null)
                    disposable.Dispose();
            }
        }

        private void EmitDefaults(object version)
        {
            // The pinned switch compares string forms: "08" and decimal 8.0 do not match 8.
            PSObject defaults = SqlConfigurationDefaults.Get(LanguagePrimitives.ConvertTo<string>(version));
            if (defaults != null)
                WriteObject(defaults);
        }
    }
}
