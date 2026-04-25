using CodexFlowWindows.Data.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CodexFlowWindows.Controls;

public sealed partial class PlanView : UserControl
{
    public static readonly DependencyProperty ExplanationProperty =
        DependencyProperty.Register(nameof(Explanation), typeof(string), typeof(PlanView), new PropertyMetadata(string.Empty, OnChanged));

    public static readonly DependencyProperty PlanProperty =
        DependencyProperty.Register(nameof(Plan), typeof(IEnumerable<PlanStep>), typeof(PlanView), new PropertyMetadata(Array.Empty<PlanStep>(), OnChanged));

    public PlanView()
    {
        InitializeComponent();
    }

    public string Explanation
    {
        get => (string)GetValue(ExplanationProperty);
        set => SetValue(ExplanationProperty, value);
    }

    public IEnumerable<PlanStep> Plan
    {
        get => (IEnumerable<PlanStep>)GetValue(PlanProperty);
        set => SetValue(PlanProperty, value);
    }

    private static void OnChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var control = (PlanView)d;
        control.ExplanationText.Text = control.Explanation;
        control.PlanItems.ItemsSource = control.Plan;
    }
}
