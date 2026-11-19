using Dataplat.Dbatools.Configuration;
using System;
using System.Collections;
using System.Linq;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands
{
    /// <summary>
    /// Implements the <c>Set-PSFConfig</c> command.
    /// </summary>
    [Cmdlet("Set", "DbatoolsConfig", DefaultParameterSetName = "FullName")]
    public partial class SetDbatoolsConfigCommand : PSCmdlet
    {
        /// <summary>
        /// The full name of the setting
        /// </summary>
        [Parameter(ParameterSetName = "FullName", Position = 0, Mandatory = true)]
        [Parameter(ParameterSetName = "Persisted", Position = 0, Mandatory = true)]
        public string FullName;

        /// <summary>
        /// The name of the module the setting belongs to.
        /// Is optional due to just specifying a name is legal, in which case the first name segment becomes the module name.
        /// </summary>
        [Parameter(ParameterSetName = "Module", Position = 0)]
        public string Module;

        /// <summary>
        /// The name of the setting within a module.
        /// </summary>
        [Parameter(ParameterSetName = "Module", Position = 1, Mandatory = true)]
        public string Name;

        /// <summary>
        /// The value to apply.
        /// </summary>
        [Parameter(ParameterSetName = "FullName", Position = 1)]
        [Parameter(ParameterSetName = "Module", Position = 2)]
        [AllowNull]
        [AllowEmptyCollection]
        [AllowEmptyString]
        public object Value;

        /// <summary>
        /// The persisted value to apply.
        /// </summary>
        [Parameter(ParameterSetName = "Persisted", Mandatory = true)]
        public string PersistedValue;

        /// <summary>
        /// The persisted type to apply.
        /// </summary>
        [Parameter(ParameterSetName = "Persisted")]
        public ConfigurationValueType PersistedType;

        /// <summary>
        /// Add documentation to the setting.
        /// </summary>
        [Parameter()]
        public string Description;

        /// <summary>
        /// The validation script to use.
        /// </summary>
        [Parameter()]
        public string Validation;

        /// <summary>
        /// The handling script to apply when changing the value.
        /// </summary>
        [Parameter()]
        public ScriptBlock Handler;

        /// <summary>
        /// Whether the setting should be hidden from casual discovery.
        /// </summary>
        [Parameter()]
        public SwitchParameter Hidden;

        /// <summary>
        /// Whether the setting should be applied only when nothing exists yet.
        /// </summary>
        [Parameter()]
        public SwitchParameter Default;

        /// <summary>
        /// Whether this is the configuration initialization call.
        /// </summary>
        [Parameter()]
        public SwitchParameter Initialize;

        /// <summary>
        /// Enabling this will cause the module to use friendly json notation on export to file.
        /// This may result in loss of data precision, but is more userfriendly.
        /// </summary>
        [Parameter()]
        public SwitchParameter SimpleExport;

        /// <summary>
        /// Whether this setting applies to module scope file export.
        /// </summary>
        [Parameter()]
        public SwitchParameter ModuleExport;

        /// <summary>
        /// Do not apply the validation script when changing values.
        /// </summary>
        [Parameter()]
        public SwitchParameter DisableValidation;

        /// <summary>
        /// Do not run the handler script when changing values.
        /// </summary>
        [Parameter()]
        public SwitchParameter DisableHandler;

        /// <summary>
        /// Return the changed configuration setting.
        /// </summary>
        [Parameter()]
        public SwitchParameter PassThru;

        /// <summary>
        /// Registers the configuration setting into the user scope.
        /// As if running Register-PSFConfig.
        /// Only applies when updating an existing setting.
        /// </summary>
        [Parameter()]
        public SwitchParameter Register;

        /// <summary>
        /// Enable throwing exceptions.
        /// </summary>
        [Parameter()]
        public SwitchParameter EnableException;

        /// <summary>
        /// The configuration item changed
        /// </summary>
        private Config _Config;

        /// <summary>
        /// Whether execution should be terminated silently.
        /// </summary>
        private bool _KillIt;

        /// <summary>
        /// Whether this is an initialization execution.
        /// </summary>
        private bool _Initialize;

        /// <summary>
        /// Whether persisted values need to be restored.
        /// </summary>
        private bool _Persisted;

        /// <summary>
        /// Whether the setting already exists.
        /// </summary>
        private bool _Exists;

        /// <summary>
        /// The setting to be affected was enforced by policy and cannot be changed by the user.
        /// </summary>
        private bool _PolicyEnforced;

        /// <summary>
        /// Processed name of module.
        /// </summary>
        private string _NameModule;

        /// <summary>
        /// Processed name of setting within module.
        /// </summary>
        private string _NameName;

        /// <summary>
        /// Processed full name of setting.
        /// </summary>
        private string _NameFull;

        /// <summary>
        /// The reason validation failed.
        /// Filled by ApplyValue.
        /// </summary>
        private string _ValidationErrorMessage;

        // These templates run through String.Format: the scriptblock braces MUST be escaped
        // as {{ }} (an unescaped "{ Stop-Function" made EVERY error path here die with
        // FormatException instead of the real message - latent until the W1-037 gate hit the
        // update-error path under the test harness), and the module lookup takes the Script
        // instance explicitly (under Invoke-ManualPester the shared engine dll registers as a
        // SECOND module also named dbatools, and `& <two modules>` is a BadExpression).
        private static string _scriptErrorValidationFullName = "$__dbatools_Module = Get-Module dbatools | Where-Object ModuleType -eq 'Script' | Select-Object -First 1\nif ($null -eq $__dbatools_Module) {{ throw 'The dbatools script module is not loaded; Import-Module dbatools before calling Set-DbatoolsConfig.' }}\n& $__dbatools_Module {{ Stop-Function -Message \"Invalid Name: {0} ! At least one '.' is required, to separate module from name\" -EnableException ${1} -Category InvalidArgument -FunctionName 'Set-DbatoolsConfig' }}";
        private static string _scriptErrorValidationName = "$__dbatools_Module = Get-Module dbatools | Where-Object ModuleType -eq 'Script' | Select-Object -First 1\nif ($null -eq $__dbatools_Module) {{ throw 'The dbatools script module is not loaded; Import-Module dbatools before calling Set-DbatoolsConfig.' }}\n& $__dbatools_Module {{ Stop-Function -Message \"Invalid Name: {0} ! Need to specify a legally namespaced name!\" -EnableException ${1} -Category InvalidArgument -FunctionName 'Set-DbatoolsConfig' }}";
        private static string _scriptErrorValidationValidation = "$__dbatools_Module = Get-Module dbatools | Where-Object ModuleType -eq 'Script' | Select-Object -First 1\nif ($null -eq $__dbatools_Module) {{ throw 'The dbatools script module is not loaded; Import-Module dbatools before calling Set-DbatoolsConfig.' }}\n& $__dbatools_Module {{ Stop-Function -Message \"Invalid validation name: {0}. Supported validations: {1}\" -EnableException ${2} -Category InvalidArgument -FunctionName 'Set-DbatoolsConfig' }}";
        private static string _updateError = "param ($Exception)\n$__dbatools_Module = Get-Module dbatools | Where-Object ModuleType -eq 'Script' | Select-Object -First 1\nif ($null -eq $__dbatools_Module) {{ throw 'The dbatools script module is not loaded; Import-Module dbatools before calling Set-DbatoolsConfig.' }}\n& $__dbatools_Module {{ Stop-Function -Message \"Could not update configuration: {0}\" -EnableException ${1} -Category InvalidArgument -Exception $Exception -FunctionName 'Set-DbatoolsConfig' }}";
        private static string _updatePolicyForbids = "$__dbatools_Module = Get-Module dbatools | Where-Object ModuleType -eq 'Script' | Select-Object -First 1\nif ($null -eq $__dbatools_Module) {{ throw 'The dbatools script module is not loaded; Import-Module dbatools before calling Set-DbatoolsConfig.' }}\n& $__dbatools_Module {{ Stop-Function -Message \"Could not update configuration: {0} - The current settings have been enforced by policy!\" -EnableException ${1} -Category PermissionDenied -FunctionName 'Set-DbatoolsConfig' }}";

        /// <summary>
        /// Implements the begin action of Set-PSFConfig
        /// </summary>
        protected override void BeginProcessing()
        {
            if (!String.IsNullOrEmpty(Validation) && !ConfigurationHost.Validation.Keys.Contains(Validation.ToLower()))
            {
                InvokeCommand.InvokeScript(String.Format(_scriptErrorValidationValidation, Validation, String.Join(", ", ConfigurationHost.Validation.Keys), EnableException.ToBool()));
                _KillIt = true;
                return;
            }

            if (!String.IsNullOrEmpty(FullName))
            {
                _NameFull = FullName.Trim('.').ToLower();
                if (!_NameFull.Contains('.'))
                {
                    InvokeCommand.InvokeScript(String.Format(_scriptErrorValidationFullName, FullName, EnableException.ToBool()));
                    _KillIt = true;
                    return;
                }

                int index = _NameFull.IndexOf('.');
                _NameModule = _NameFull.Substring(0, index);
                _NameName = _NameFull.Substring(index + 1);
            }
            else
            {
                if (!String.IsNullOrEmpty(Module))
                {
                    _NameModule = Module.Trim('.', ' ').ToLower();
                    _NameName = Name.Trim('.', ' ').ToLower();
                    _NameFull = String.Format("{0}.{1}", _NameModule, _NameName);
                }
                else
                {
                    _NameFull = Name.Trim('.').ToLower();
                    if (!_NameFull.Contains('.'))
                    {
                        InvokeCommand.InvokeScript(String.Format(_scriptErrorValidationFullName, Name, EnableException.ToBool()));
                        _KillIt = true;
                        return;
                    }

                    int index = _NameFull.IndexOf('.');
                    _NameModule = _NameFull.Substring(0, index);
                    _NameName = _NameFull.Substring(index + 1);
                }
            }

            if (String.IsNullOrEmpty(_NameModule) || String.IsNullOrEmpty(_NameName))
            {
                InvokeCommand.InvokeScript(String.Format(_scriptErrorValidationName, _NameFull, EnableException.ToBool()));
                _KillIt = true;
                return;
            }

            _Exists = ConfigurationHost.Configurations.TryGetValue(_NameFull, out _Config);
            _Initialize = Initialize;
            _Persisted = !String.IsNullOrEmpty(PersistedValue);
            _PolicyEnforced = (_Exists && _Config.PolicyEnforced);

            // If the setting is already initialized, nothing should be done
            if (_Exists && _Config.Initialized && Initialize)
                _KillIt = true;
        }

        /// <summary>
        /// Implements the process action of Set-PSFConfig
        /// </summary>
        protected override void ProcessRecord()
        {
            if (_KillIt)
                return;

            if (_Initialize)
                ExecuteInitialize();
            else if (!_Exists && _Persisted)
                ExecuteNewPersisted();
            else if (_Exists && _Persisted)
                ExecuteUpdatePersisted();
            else if (_Exists)
                ExecuteUpdate();
            else
                ExecuteNew();

            if (PassThru.ToBool() && (_Config != null))
                WriteObject(_Config);
        }
    }
}
