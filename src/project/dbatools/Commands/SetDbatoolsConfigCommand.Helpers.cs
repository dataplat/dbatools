using Dataplat.Dbatools.Configuration;
using System;
using System.Collections;
using System.Linq;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands
{
    public partial class SetDbatoolsConfigCommand
    {
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

            if (!DisableValidation.ToBool() && (!String.IsNullOrEmpty(_Config.Validation)))
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

            if (!DisableHandler.ToBool() && (_Config.Handler != null))
            {
                object handlerValue = tempValue;
                ScriptBlock tempHandler = ScriptBlock.Create(_Config.Handler.ToString());
                if ((tempValue != null) && ((tempValue as ICollection) != null))
                    handlerValue = new object[1] { tempValue };

                tempHandler.Invoke(handlerValue);
            }

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
    }
}
