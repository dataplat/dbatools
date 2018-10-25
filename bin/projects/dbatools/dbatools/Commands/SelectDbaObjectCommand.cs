using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Text;
using System.Threading.Tasks;
using Sqlcollaborative.Dbatools.Parameter;

namespace Sqlcollaborative.Dbatools.Commands
{
    /// <summary>
    /// Implements the Select-DbaObject command
    /// </summary>
    [Cmdlet("Select", "DbaObject", DefaultParameterSetName = "DefaultParameter", RemotingCapability = RemotingCapability.None)]
    public class SelectDbaObjectCommand : PSCmdlet
    {
        #region Parameters
        /// <summary>
        /// The actual input object that is being processed
        /// </summary>
        [Parameter(ValueFromPipeline = true)]
        public PSObject InputObject;

        /// <summary>
        /// The properties to select. Supports fancy DSL
        /// </summary>
        [Parameter(ParameterSetName = "DefaultParameter", Position = 0)]
        [Parameter(ParameterSetName = "SkipLastParameter", Position = 0)]
        public DbaSelectParameter[] Property = new DbaSelectParameter[0];

        /// <summary>
        /// Properties to skip
        /// </summary>
        [Parameter(ParameterSetName = "DefaultParameter")]
        [Parameter(ParameterSetName = "SkipLastParameter")]
        public string[] ExcludeProperty = new string[0];

        /// <summary>
        /// A property to expand.
        /// </summary>
        [Parameter(ParameterSetName = "DefaultParameter")]
        [Parameter(ParameterSetName = "SkipLastParameter")]
        public string ExpandProperty;

        /// <summary>
        /// Whether to exclude duplicates
        /// </summary>
        [Parameter()]
        public SwitchParameter Unique;

        /// <summary>
        /// The last number of items to pick
        /// </summary>
        [Parameter(ParameterSetName = "DefaultParameter")]
        [ValidateRange(0, 2147483647)]
        public int Last;

        /// <summary>
        /// Pick the first n items.
        /// </summary>
        [Parameter(ParameterSetName = "DefaultParameter")]
        [ValidateRange(0, 2147483647)]
        public int First;

        /// <summary>
        /// Skip n items before picking items
        /// </summary>
        [Parameter(ParameterSetName = "DefaultParameter")]
        [ValidateRange(0, 2147483647)]
        public int Skip;

        /// <summary>
        /// Skip the last n items
        /// </summary>
        [Parameter(ParameterSetName = "SkipLastParameter")]
        [ValidateRange(0, 2147483647)]
        public int SkipLast;

        /// <summary>
        /// 
        /// </summary>
        [Parameter(ParameterSetName = "IndexParameter")]
        [Parameter(ParameterSetName = "DefaultParameter")]
        public SwitchParameter Wait;

        /// <summary>
        /// 
        /// </summary>
        [Parameter(ParameterSetName = "IndexParameter")]
        [ValidateRange(0, 2147483647)]
        public int[] Index;

        /// <summary>
        /// THe properties to display by default
        /// </summary>
        [Parameter()]
        public string[] ShowProperty = new string[0];

        /// <summary>
        /// The properties to NOT display by default
        /// </summary>
        [Parameter()]
        public string[] ShowExcludeProperty = new string[0];

        /// <summary>
        /// The typename to assign to the psobject
        /// </summary>
        [Parameter()]
        public string TypeName;

        /// <summary>
        /// Keep the original input object, just add to it.
        /// </summary>
        [Parameter()]
        public SwitchParameter KeepInputObject;
        #endregion Parameters

        #region Private Fields
        /// <summary>
        /// List of properties to NOT clone into the hashtable used against Select-Object
        /// </summary>
        private string[] _NonclonedProperties = new string[] { "Property", "ShowProperty", "ShowExcludeProperty", "TypeName", "KeepInputObject" };

        /// <summary>
        /// Whether some adjustments to the object need to be done or whether the Select-Object output can be simply passed through.
        /// </summary>
        private bool _NoAdjustment = true;

        /// <summary>
        /// The set controlling what properties will be shown by default
        /// </summary>
        private PSMemberInfo[] _DisplayPropertySet;

        /// <summary>
        /// THe pipeline that is wrapped around Select-Object
        /// </summary>
        private SteppablePipeline _Pipeline;
        #endregion Private Fields

        #region Command Implementation
        /// <summary>
        /// Implements the begin action of the command
        /// </summary>
        protected override void BeginProcessing()
        {
            object outBuffer;
            if (MyInvocation.BoundParameters.TryGetValue("OutBuffer", out outBuffer))
            {
                MyInvocation.BoundParameters["OutBuffer"] = 1;
            }

            Hashtable clonedBoundParameters = new Hashtable();
            foreach (string key in MyInvocation.BoundParameters.Keys)
                if (!_NonclonedProperties.Contains(key))
                    clonedBoundParameters[key] = MyInvocation.BoundParameters[key];

            if (MyInvocation.BoundParameters.ContainsKey("Property"))
                clonedBoundParameters["Property"] = Property.Select(o => o.Value).AsEnumerable().ToArray();

            if ((ShowExcludeProperty.Length > 0) || (ShowProperty.Length > 0) || (!String.IsNullOrEmpty(TypeName)) || (KeepInputObject.ToBool()))
                _NoAdjustment = false;

            if (ShowProperty.Length > 0)
                _DisplayPropertySet = new PSMemberInfo[] { new PSPropertySet("DefaultDisplayPropertySet", ShowProperty) };

            // Set the list of parameters to a variable in the caller scope, so it can be splatted
            this.SessionState.PSVariable.Set("__PSFramework_SelectParam", clonedBoundParameters);
            ScriptBlock scriptCommand = ScriptBlock.Create("Select-Object @__PSFramework_SelectParam");
            _Pipeline = scriptCommand.GetSteppablePipeline(MyInvocation.CommandOrigin);

            if (_NoAdjustment)
                _Pipeline.Begin(this);
            else
                _Pipeline.Begin(true);
        }

        /// <summary>
        /// Implements the process action of the command
        /// </summary>
        protected override void ProcessRecord()
        {
            if (_NoAdjustment)
                _Pipeline.Process(InputObject);
            else
            {
                PSObject item = PSObject.AsPSObject(_Pipeline.Process(InputObject).GetValue(0));

                if (KeepInputObject.ToBool())
                {
                    PSObject tempItem = item;
                    item = InputObject;
                    foreach (PSPropertyInfo info in tempItem.Properties.Where(o => !item.Properties.Select(n => n.Name).Contains(o.Name)))
                        item.Properties.Add(info);
                }
                if (ShowProperty.Length > 0)
                    item.Members.Add(new PSMemberSet("PSStandardMembers", _DisplayPropertySet));
                else if (ShowExcludeProperty.Length > 0)
                    item.Members.Add(new PSMemberSet("PSStandardMembers", new PSMemberInfo[] { new PSPropertySet("DefaultDisplayPropertySet", item.Properties.Select(o => o.Name).Where(o => !ShowExcludeProperty.Contains(o))) }));
                if (!String.IsNullOrEmpty(TypeName))
                    item.TypeNames.Insert(0, TypeName);
                WriteObject(item);
            }
        }

        /// <summary>
        /// Implements the end action of the command
        /// </summary>
        protected override void EndProcessing()
        {
            _Pipeline.End();
        }
        #endregion Command Implementation
    }
}
