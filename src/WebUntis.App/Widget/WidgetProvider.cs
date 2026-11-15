using System.Collections.Concurrent;
using Microsoft.Windows.Widgets.Providers;

namespace WebUntis.App.Widget;

public sealed class WidgetProvider : IWidgetProvider
{
    public const string DefinitionId = "WebUntis_Today";

    private const string Template = """
        {
          "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
          "type": "AdaptiveCard",
          "version": "1.5",
          "body": [
            {
              "type": "TextBlock",
              "text": "WebUntis",
              "weight": "Bolder",
              "wrap": true
            },
            {
              "type": "TextBlock",
              "text": "${message}",
              "wrap": true,
              "spacing": "Small"
            }
          ]
        }
        """;

    private static readonly ConcurrentDictionary<string, WidgetInstance> RunningWidgets = new();
    private static readonly ManualResetEventSlim EmptyList = new(false);

    public WidgetProvider()
    {
        foreach (var widgetInfo in WidgetManager.GetDefault().GetWidgetInfos())
        {
            var context = widgetInfo.WidgetContext;
            if (context is null)
            {
                continue;
            }

            Remember(context.Id, context.DefinitionId);
        }
    }

    public static void WaitUntilEmpty()
    {
        EmptyList.Wait();
    }

    public void CreateWidget(WidgetContext widgetContext)
    {
        var instance = Remember(widgetContext.Id, widgetContext.DefinitionId);
        UpdateWidget(instance);
    }

    public void DeleteWidget(string widgetId, string customState)
    {
        RunningWidgets.TryRemove(widgetId, out _);
        if (RunningWidgets.IsEmpty)
        {
            EmptyList.Set();
        }
    }

    public void OnActionInvoked(WidgetActionInvokedArgs actionInvokedArgs)
    {
    }

    public void OnWidgetContextChanged(WidgetContextChangedArgs contextChangedArgs)
    {
        var context = contextChangedArgs.WidgetContext;
        if (RunningWidgets.TryGetValue(context.Id, out var instance))
        {
            UpdateWidget(instance);
        }
    }

    public void Activate(WidgetContext widgetContext)
    {
        var instance = Remember(widgetContext.Id, widgetContext.DefinitionId);
        instance.IsActive = true;
        UpdateWidget(instance);
    }

    public void Deactivate(string widgetId)
    {
        if (RunningWidgets.TryGetValue(widgetId, out var instance))
        {
            instance.IsActive = false;
        }
    }

    private static WidgetInstance Remember(string widgetId, string definitionId)
    {
        return RunningWidgets.GetOrAdd(widgetId, id => new WidgetInstance(id, definitionId));
    }

    private static void UpdateWidget(WidgetInstance instance)
    {
        var update = new WidgetUpdateRequestOptions(instance.WidgetId)
        {
            Template = Template,
            Data = """{"message":"Open the WebUntis app to sign in. Timetable data is not connected yet."}""",
            CustomState = string.Empty,
            IsPlaceholderContent = true
        };

        WidgetManager.GetDefault().UpdateWidget(update);
    }

    private sealed class WidgetInstance(string widgetId, string definitionId)
    {
        public string WidgetId { get; } = widgetId;
        public string DefinitionId { get; } = definitionId;
        public bool IsActive { get; set; }
    }
}
