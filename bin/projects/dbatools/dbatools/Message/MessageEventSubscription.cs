using Sqlcollaborative.Dbatools.Utility;
using System;
using System.Collections.Generic;
using System.Management.Automation;

namespace Sqlcollaborative.Dbatools.Message
{
    /// <summary>
    /// Condition and logic to be executed on message events
    /// </summary>
    public class MessageEventSubscription
    {
        /// <summary>
        /// Name of the event subscription, must be unique.
        /// </summary>
        public string Name;

        /// <summary>
        /// Scriptblock to execute if the condition is met
        /// </summary>
        public ScriptBlock ScriptBlock;

        /// <summary>
        /// The internally stored filter value for Message
        /// </summary>
        private string _MessageFilter;
        /// <summary>
        /// The value the Message is filtered by
        /// </summary>
        public string MessageFilter
        {
            get { return _MessageFilter; }
            set
            {
                _MessageFilter = value;
                MessageFilterSet = true;
            }
        }
        /// <summary>
        /// Whether filtering by Message was enabled
        /// </summary>
        public bool MessageFilterSet { get; private set; }

        /// <summary>
        /// The internally stored filter value for ModuleName
        /// </summary>
        private string _ModuleNameFilter;
        /// <summary>
        /// The value the ModuleName is filtered by
        /// </summary>
        public string ModuleNameFilter
        {
            get { return _ModuleNameFilter; }
            set
            {
                _ModuleNameFilter = value;
                ModuleNameFilterSet = true;
            }
        }
        /// <summary>
        /// Whether filtering by ModuleName was enabled
        /// </summary>
        public bool ModuleNameFilterSet { get; private set; }

        /// <summary>
        /// The internally stored filter value for FunctionName
        /// </summary>
        private string _FunctionNameFilter;
        /// <summary>
        /// The value the FunctionName is filtered by
        /// </summary>
        public string FunctionNameFilter
        {
            get { return _FunctionNameFilter; }
            set
            {
                _FunctionNameFilter = value;
                FunctionNameFilterSet = true;
            }
        }
        /// <summary>
        /// Whether filtering by FunctionName was enabled
        /// </summary>
        public bool FunctionNameFilterSet { get; private set; }

        /// <summary>
        /// The internally stored filter value for Target
        /// </summary>
        private object _TargetFilter;
        /// <summary>
        /// The value the Target is filtered by
        /// </summary>
        public object TargetFilter
        {
            get { return _TargetFilter; }
            set
            {
                _TargetFilter = value;
                TargetFilterSet = true;
            }
        }
        /// <summary>
        /// Whether filtering by Target was enabled
        /// </summary>
        public bool TargetFilterSet { get; private set; }

        /// <summary>
        /// The internally stored filter value for Level
        /// </summary>
        private List<MessageLevel> _LevelFilter;
        /// <summary>
        /// The value the Level is filtered by
        /// </summary>
        public List<MessageLevel> LevelFilter
        {
            get { return _LevelFilter; }
            set
            {
                _LevelFilter = value;
                LevelFilterSet = true;
            }
        }
        /// <summary>
        /// Whether filtering by Level was enabled
        /// </summary>
        public bool LevelFilterSet { get; private set; }

        /// <summary>
        /// The internally stored filter value for Tag
        /// </summary>
        private List<string> _TagFilter;
        /// <summary>
        /// The value the Tag is filtered by
        /// </summary>
        public List<string> TagFilter
        {
            get { return _TagFilter; }
            set
            {
                _TagFilter = value;
                TagFilterSet = true;
            }
        }
        /// <summary>
        /// Whether filtering by Tag was enabled
        /// </summary>
        public bool TagFilterSet { get; private set; }

        /// <summary>
        /// The internally stored filter value for Runspace
        /// </summary>
        private Guid _RunspaceFilter;
        /// <summary>
        /// The value the Runspace is filtered by
        /// </summary>
        public Guid RunspaceFilter
        {
            get { return _RunspaceFilter; }
            set
            {
                _RunspaceFilter = value;
                RunspaceFilterSet = true;
            }
        }
        /// <summary>
        /// Whether filtering by Runspace was enabled
        /// </summary>
        public bool RunspaceFilterSet { get; private set; }

        /// <summary>
        /// Checks, whether a given entry matches the filter defined in this subscription
        /// </summary>
        /// <param name="Entry">The entry to validate</param>
        /// <returns>Whether the subscription should react to this entry</returns>
        public bool Applies(LogEntry Entry)
        {
            if (MessageFilterSet && !UtilityHost.IsLike(Entry.Message, MessageFilter))
                return false;
            if (ModuleNameFilterSet && !UtilityHost.IsLike(Entry.ModuleName, ModuleNameFilter))
                return false;
            if (FunctionNameFilterSet && !UtilityHost.IsLike(Entry.FunctionName, FunctionNameFilter))
                return false;
            if (TargetFilterSet && (Entry.TargetObject != TargetFilter))
                return false;
            if (LevelFilterSet && !LevelFilter.Contains(Entry.Level))
                return false;
            if (TagFilterSet)
            {
                bool test = false;

                foreach (string tag in TagFilter)
                    foreach (string tag2 in Entry.Tags)
                        if (tag == tag2)
                            test = true;

                if (!test)
                    return false;
            }
            if (RunspaceFilterSet && RunspaceFilter != Entry.Runspace)
                return false;

            return true;
        }
    }
}
