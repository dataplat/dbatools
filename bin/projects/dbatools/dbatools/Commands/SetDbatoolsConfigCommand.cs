using Sqlcollaborative.Dbatools.Configuration;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;

namespace Sqlcollaborative.Dbatools.Commands
{
    /// <summary>
    /// Implements the Set-PSFConfig command
    /// </summary>
    [Cmdlet("Set", "DbatoolsConfig", DefaultParameterSetName = "FullName")]
    public class SetDbatoolsConfigCommand : PSCmdlet
    {
        #region Parameters
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
        #endregion Parameters

        #region Private fields
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
        #endregion Private fields

        #region Internal Resources
        private static string _scriptErrorValidationFullName = "$__dbatools_Module = Get-Module dbatools\n& $__dbatools_Module { Stop-Function -Message \"Invalid Name: {0} ! At least one '.' is required, to separate module from name\" -EnableException ${1} -Category InvalidArgument -FunctionName 'Set-DbatoolsConfig' }";
        private static string _scriptErrorValidationName = "$__dbatools_Module = Get-Module dbatools\n& $__dbatools_Module { Stop-Function -Message \"Invalid Name: {0} ! Need to specify a legally namespaced name!\" -EnableException ${1} -Category InvalidArgument -FunctionName 'Set-DbatoolsConfig' }";
        private static string _scriptErrorValidationValidation = "$__dbatools_Module = Get-Module dbatools\n& $__dbatools_Module { Stop-Function -Message \"Invalid validation name: {0}. Supported validations: {1}\" -EnableException ${2} -Category InvalidArgument -FunctionName 'Set-DbatoolsConfig' }";
        private static string _updateError = "param ($Exception)\n$__dbatools_Module = Get-Module dbatools\n& $__dbatools_Module { Stop-Function -Message \"Could not update configuration: {0}\" -EnableException ${1} -Category InvalidArgument -Exception $Exception -FunctionName 'Set-DbatoolsConfig' }";
        private static string _updatePolicyForbids = "$__dbatools_Module = Get-Module dbatools\n& $__dbatools_Module { Stop-Function -Message \"Could not update configuration: {0} - The current settings have been enforced by policy!\" -EnableException ${1} -Category PermissionDenied -FunctionName 'Set-DbatoolsConfig' }";
        #endregion Internal Resources

        #region Cmdlet methods
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

            #region Name Interpretation
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
            #endregion Name Interpretation

            _Exists = ConfigurationHost.Configurations.ContainsKey(_NameFull);
            if (_Exists)
                _Config = ConfigurationHost.Configurations[_NameFull];
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
        #endregion Cmdlet methods

        #region Private Methods
        private void ExecuteInitialize()
        {
            object oldValue = null;
            if (_Exists)
                oldValue = _Config.Value;
            else
                _Config = new Config();

            _Config.Name = _NameName;
            _Config.Module = _NameModule;
            _Config.Value = Value;

            ApplyCommonSettings();

            _Config.Initialized = true;
            ConfigurationHost.Configurations[_NameFull] = _Config;

            if (_Exists)
            {
                try { ApplyValue(oldValue); }
                catch (Exception e)
                {
                    InvokeCommand.InvokeScript(true, ScriptBlock.Create(String.Format(_updateError, _NameFull, EnableException.ToBool())), null, e);
                    _KillIt = true;
                    return;
                }
            }
        }

        private void ExecuteNew()
        {
            _Config = new Config();
            _Config.Name = _NameName;
            _Config.Module = _NameModule;
            _Config.Value = Value;
            ApplyCommonSettings();
            ConfigurationHost.Configurations[_NameFull] = _Config;
        }

        private void ExecuteUpdate()
        {
            if (_PolicyEnforced)
            {
                InvokeCommand.InvokeScript(String.Format(_updatePolicyForbids, _NameFull, EnableException.ToBool()));
                _KillIt = true;
                return;
            }
            ApplyCommonSettings();

            if (!MyInvocation.BoundParameters.ContainsKey("Value"))
                return;

            try
            {
                if (!Default)
                    ApplyValue(Value);
            }
            catch (Exception e)
            {
                InvokeCommand.InvokeScript(true, ScriptBlock.Create(String.Format(_updateError, _NameFull, EnableException.ToBool())), null, e);
                _KillIt = true;
                return;
            }
        }

        private void ExecuteNewPersisted()
        {
            _Config = new Config();
            _Config.Name = _NameName;
            _Config.Module = _NameModule;
            _Config.SetPersistedValue(PersistedType, PersistedValue);
            ApplyCommonSettings();
            ConfigurationHost.Configurations[_NameFull] = _Config;
        }

        private void ExecuteUpdatePersisted()
        {
            if (_PolicyEnforced)
            {
                InvokeCommand.InvokeScript(String.Format(_updatePolicyForbids, _NameFull, EnableException.ToBool()));
                _KillIt = true;
                return;
            }

            _Config.SetPersistedValue(PersistedType, PersistedValue);
            ApplyCommonSettings();
            ConfigurationHost.Configurations[_NameFull] = _Config;
        }

        /// <summary>
        /// Applies a value to a configuration item, invoking validation and handler scriptblocks.
        /// </summary>
        /// <param name="Value">The value to apply</param>
        private void ApplyValue(object Value)
        {
            object tempValue = Value;

            #region Validation
            if (!DisableValidation.ToBool() && (_Config.Validation != null))
            {
                ScriptBlock tempValidation = ScriptBlock.Create(_Config.Validation.ToString());
                //if ((tempValue != null) && ((tempValue as ICollection) != null))
                //    tempValue = new object[1] { tempValue };

                PSObject validationResult = tempValidation.Invoke(tempValue)[0];
                if (!(bool)validationResult.Properties["Success"].Value)
                {
                    _ValidationErrorMessage = (string)validationResult.Properties["Message"].Value;
                    throw new ArgumentException(String.Format("Failed validation: {0}", _ValidationErrorMessage));
                }
                tempValue = validationResult.Properties["Value"].Value;
            }
            #endregion Validation

            #region Handler
            if (!DisableHandler.ToBool() && (_Config.Handler != null))
            {
                object handlerValue = tempValue;
                ScriptBlock tempHandler = ScriptBlock.Create(_Config.Handler.ToString());
                if ((tempValue != null) && ((tempValue as ICollection) != null))
                    handlerValue = new object[1] { tempValue };

                tempHandler.Invoke(handlerValue);
            }
            #endregion Handler

            _Config.Value = tempValue;

            if (Register.ToBool())
            {
                ScriptBlock registerCodeblock = ScriptBlock.Create(@"
param ($Config)
$Config | Register-DbatoolsConfig
");
                registerCodeblock.Invoke(_Config);
            }
        }

        /// <summary>
        /// Abstracts out 
        /// </summary>
        private void ApplyCommonSettings()
        {
            if (!String.IsNullOrEmpty(Description))
                _Config.Description = Description;
            if (Handler != null)
                _Config.Handler = Handler;
            if (!String.IsNullOrEmpty(Validation))
                _Config.Validation = ConfigurationHost.Validation[Validation.ToLower()];
            if (Hidden.IsPresent)
                _Config.Hidden = Hidden;
            if (SimpleExport.IsPresent)
                _Config.SimpleExport = SimpleExport;
            if (ModuleExport.IsPresent)
                _Config.ModuleExport = ModuleExport;
        }
        #endregion Private Methods
    }
}
