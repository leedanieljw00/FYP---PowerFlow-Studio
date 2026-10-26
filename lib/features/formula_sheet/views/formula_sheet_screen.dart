import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class FormulaCategory {
  const FormulaCategory({
    required this.title,
    required this.description,
    required this.items,
  });

  final String title;
  final String description;
  final List<FormulaItem> items;
}

class FormulaItem {
  const FormulaItem({
    required this.name,
    required this.tex,
    required this.explanation,
    this.variables = const {},
  });

  final String name;
  final String tex;
  final String explanation;
  final Map<String, String> variables;
}

class FormulaSheetScreen extends StatefulWidget {
  const FormulaSheetScreen({super.key});

  @override
  State<FormulaSheetScreen> createState() => _FormulaSheetScreenState();
}

class _FormulaSheetScreenState extends State<FormulaSheetScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const List<FormulaCategory> _categories = [
    FormulaCategory(
      title: 'Bus Admittance Matrix (Y_bus)',
      description: 'System matrix formulation using nominal-π line models and off-nominal transformer taps.',
      items: [
        FormulaItem(
          name: 'Off-Diagonal Elements (Mutual Admittance)',
          tex: r'Y_{ij} = Y_{ji} = -\frac{y_{ij}}{a_{ij}}',
          explanation:
              'Negative of the series admittance connecting bus i and bus j. If a transformer has tap ratio a on bus i, the mutual admittance is scaled by 1/a.',
          variables: {
            r'y_{ij}': r'Series admittance: 1 / (R_{ij} + jX_{ij})',
            r'a_{ij}': r'Off-nominal tap ratio on sending end bus i',
          },
        ),
        FormulaItem(
          name: 'Diagonal Elements (Self Admittance)',
          tex: r'Y_{ii} = y_{ii0} + \sum_{j \neq i} \left( \frac{y_{ij}}{a_{ij}^2} + j\frac{B_{ij}}{2} \right)',
          explanation:
              'Sum of all branch admittances connected to bus i, including shunt charging susceptances B/2 and shunt capacitor/reactor banks.',
          variables: {
            r'y_{ii0}': r'Fixed bus shunt admittance to ground',
            r'B_{ij}/2': r'Half-line charging susceptance at bus i',
          },
        ),
      ],
    ),
    FormulaCategory(
      title: 'Power Flow Injections (Polar Form)',
      description: 'Non-linear power balance equations governing bus voltages and complex injections.',
      items: [
        FormulaItem(
          name: 'Complex Power Injection',
          tex: r'S_i = P_i + jQ_i = V_i I_i^* = V_i \left( \sum_{k=1}^N Y_{ik} V_k \right)^*',
          explanation:
              'Net complex power injected into the transmission network at bus i in terms of bus voltages and Y_bus.',
        ),
        FormulaItem(
          name: 'Real Power Injection Equation',
          tex: r'P_i = \sum_{k=1}^N |V_i| |V_k| |Y_{ik}| \cos(\theta_{ik} - \delta_i + \delta_k)',
          explanation:
              'Analytical equation for active power injection at bus i in polar coordinates (voltage magnitude |V| and angle δ).',
          variables: {
            r'|Y_{ik}|, \theta_{ik}': r'Magnitude and phase angle of Y_bus entry Y_{ik}',
            r'|V_i|, \delta_i': r'Voltage magnitude and phase angle at bus i',
          },
        ),
        FormulaItem(
          name: 'Reactive Power Injection Equation',
          tex: r'Q_i = -\sum_{k=1}^N |V_i| |V_k| |Y_{ik}| \sin(\theta_{ik} - \delta_i + \delta_k)',
          explanation:
              'Analytical equation for reactive power injection at bus i in polar coordinates.',
        ),
      ],
    ),
    FormulaCategory(
      title: 'Newton-Raphson Solver & Jacobian Matrix',
      description: 'Second-order convergent iterative method using first-order Taylor expansion.',
      items: [
        FormulaItem(
          name: 'Newton-Raphson System of Equations',
          tex: r'\begin{bmatrix} \Delta P \\ \Delta Q \end{bmatrix} = \begin{bmatrix} J_1 & J_2 \\ J_3 & J_4 \end{bmatrix} \begin{bmatrix} \Delta \delta \\ \Delta |V| \end{bmatrix}',
          explanation:
              'Matrix equation solved at each iteration k for angle corrections Δδ and voltage magnitude corrections Δ|V|.',
          variables: {
            r'\Delta P_i': r'Real power mismatch: P_i^{sch} - P_i^{calc}',
            r'\Delta Q_i': r'Reactive power mismatch: Q_i^{sch} - Q_i^{calc}',
          },
        ),
        FormulaItem(
          name: 'Sub-matrix J_1 (∂P / ∂δ)',
          tex: r'\begin{aligned} \frac{\partial P_i}{\partial \delta_k} &= -|V_i||V_k||Y_{ik}|\sin(\theta_{ik} - \delta_i + \delta_k), \quad (k \neq i) \\ \frac{\partial P_i}{\partial \delta_i} &= \sum_{k \neq i} |V_i||V_k||Y_{ik}|\sin(\theta_{ik} - \delta_i + \delta_k) \end{aligned}',
          explanation:
              'Sensitivity of real power injections with respect to bus voltage angles.',
        ),
        FormulaItem(
          name: 'Sub-matrix J_2 (∂P / ∂|V|)',
          tex: r'\begin{aligned} \frac{\partial P_i}{\partial |V_k|} &= |V_i||Y_{ik}|\cos(\theta_{ik} - \delta_i + \delta_k), \quad (k \neq i) \\ \frac{\partial P_i}{\partial |V_i|} &= 2|V_i||Y_{ii}|\cos\theta_{ii} + \sum_{k \neq i}|V_k||Y_{ik}|\cos(\theta_{ik} - \delta_i + \delta_k) \end{aligned}',
          explanation:
              'Sensitivity of real power injections with respect to bus voltage magnitudes.',
        ),
        FormulaItem(
          name: 'Sub-matrix J_3 (∂Q / ∂δ)',
          tex: r'\begin{aligned} \frac{\partial Q_i}{\partial \delta_k} &= -|V_i||V_k||Y_{ik}|\cos(\theta_{ik} - \delta_i + \delta_k), \quad (k \neq i) \\ \frac{\partial Q_i}{\partial \delta_i} &= \sum_{k \neq i} |V_i||V_k||Y_{ik}|\cos(\theta_{ik} - \delta_i + \delta_k) \end{aligned}',
          explanation:
              'Sensitivity of reactive power injections with respect to bus voltage angles.',
        ),
        FormulaItem(
          name: 'Sub-matrix J_4 (∂Q / ∂|V|)',
          tex: r'\begin{aligned} \frac{\partial Q_i}{\partial |V_k|} &= -|V_i||Y_{ik}|\sin(\theta_{ik} - \delta_i + \delta_k), \quad (k \neq i) \\ \frac{\partial Q_i}{\partial |V_i|} &= -2|V_i||Y_{ii}|\sin\theta_{ii} - \sum_{k \neq i}|V_k||Y_{ik}|\sin(\theta_{ik} - \delta_i + \delta_k) \end{aligned}',
          explanation:
              'Sensitivity of reactive power injections with respect to bus voltage magnitudes.',
        ),
      ],
    ),
    FormulaCategory(
      title: 'Gauss-Seidel Solver',
      description: 'Successive displacement method updating voltages bus-by-bus.',
      items: [
        FormulaItem(
          name: 'PQ Bus Voltage Update Equation',
          tex: r'V_i^{(k+1)} = \frac{1}{Y_{ii}} \left( \frac{P_i - jQ_i}{(V_i^{(k)})^*} - \sum_{j=1}^{i-1} Y_{ij} V_j^{(k+1)} - \sum_{j=i+1}^N Y_{ij} V_j^{(k)} \right)',
          explanation:
              'Updated phasor voltage for bus i, immediately utilizing updated voltages V_j^{(k+1)} for buses j < i.',
        ),
        FormulaItem(
          name: 'PV Bus Reactive Power Calculation',
          tex: r'Q_i^{(k+1)} = -\operatorname{Im}\left\{ (V_i^{(k)})^* \left[ \sum_{j=1}^{i-1} Y_{ij} V_j^{(k+1)} + \sum_{j=i}^N Y_{ij} V_j^{(k)} \right] \right\}',
          explanation:
              'Estimated reactive power generation to maintain specified voltage magnitude. If Q_i exceeds Q_min or Q_max, Q_i is clamped and the bus is treated as PQ for that sweep.',
        ),
        FormulaItem(
          name: 'Successive Over-Relaxation (Acceleration)',
          tex: r'V_{i,\text{acc}}^{(k+1)} = V_i^{(k)} + \alpha \left( V_i^{(k+1)} - V_i^{(k)} \right)',
          explanation:
              'Acceleration factor α (typically 1.3 to 1.6) applied to accelerate Gauss-Seidel convergence.',
        ),
      ],
    ),
    FormulaCategory(
      title: 'Line Flows & System Losses',
      description: 'Evaluation of transmission branch flows and total active/reactive grid losses.',
      items: [
        FormulaItem(
          name: 'Sending-End Power Flow (S_ij)',
          tex: r'S_{ij} = P_{ij} + jQ_{ij} = V_i I_{ij}^* = V_i \left( [V_i - V_j] y_{ij} + V_i \cdot j\frac{B_{ij}}{2} \right)^*',
          explanation:
              'Complex power flowing from bus i into the branch connected to bus j.',
        ),
        FormulaItem(
          name: 'Branch Power Loss (S_{L,ij})',
          tex: r'S_{L,ij} = S_{ij} + S_{ji} = (P_{ij} + P_{ji}) + j(Q_{ij} + Q_{ji})',
          explanation:
              'Active (I^2 R) and reactive power lost in branch ij due to series impedance and shunt susceptance.',
        ),
      ],
    ),
    FormulaCategory(
      title: 'Economic Dispatch (ED)',
      description: 'Optimal real power allocation minimizing total operational fuel cost with and without transmission losses.',
      items: [
        FormulaItem(
          name: 'Thermal Generator Fuel Cost & Incremental Cost Rate (ICR)',
          tex: r'C_i(P_i) = \alpha_i + \beta_i P_i + \gamma_i P_i^2, \quad \text{ICR}_i = \frac{dC_i}{dP_i} = \beta_i + 2\gamma_i P_i',
          explanation:
              'Quadratic fuel production cost function in \$/h and its marginal incremental cost rate in \$/MWh.',
          variables: {
            r'\alpha_i, \beta_i, \gamma_i': r'Cost curve coefficients',
            r'P_i': r'Generator active power output (MW)',
          },
        ),
        FormulaItem(
          name: 'Lossless Dispatch Equal Incremental Fuel Cost (λ)',
          tex: r'\lambda = \frac{P_D + \sum_{i=1}^n \frac{\beta_i}{2\gamma_i}}{\sum_{i=1}^n \frac{1}{2\gamma_i}}, \quad P_{Gi} = \frac{\lambda - \beta_i}{2\gamma_i}',
          explanation:
              'Equal slope criterion when transmission losses are neglected. Clamped generators violating limits P_min or P_max are fixed and demand is adjusted iteratively.',
        ),
        FormulaItem(
          name: 'Loss-Included Coordination Equation & Penalty Factor (L_i)',
          tex: r'L_i \times \text{ICR}_i = \lambda \implies \left( \frac{1}{1 - \frac{\partial P_L}{\partial P_{Gi}}} \right) (\beta_i + 2\gamma_i P_{Gi}) = \lambda',
          explanation:
              'Optimal dispatch condition including grid losses, where L_i is the transmission penalty factor of generator i.',
          variables: {
            r'\frac{\partial P_L}{\partial P_{Gi}}': r'Incremental transmission loss: 2\sum_j B_{ij}P_{Gj} + B_{0i}',
          },
        ),
        FormulaItem(
          name: "Kron's Transmission Loss Formula",
          tex: r'P_L = \sum_{i} \sum_{j} P_{Gi} B_{ij} P_{Gj} + \sum_i B_{0i} P_{Gi} + B_{00}',
          explanation:
              "Approximation of total active power grid losses expressed as a quadratic function of generator power injections via B-coefficients.",
        ),
      ],
    ),
    FormulaCategory(
      title: 'Load Frequency Control (LFC) & Droop',
      description: 'Primary governor droop regulation, composite frequency response, and two-area tie-line control.',
      items: [
        FormulaItem(
          name: 'Composite Frequency Response Characteristic (β_sys)',
          tex: r'\beta_{\text{sys}} = D + \sum_{i=1}^n \frac{1}{R_{i,\text{sys}}} \quad (\text{pu/pu})',
          explanation:
              'System stiffness combining load-damping constant D and all active generator speed droops R_i on a common MVA base.',
          variables: {
            r'R_{i,\text{sys}}': r'Speed droop on system base: R_{i,\text{unit}} \times (S_{\text{base,sys}} / S_{\text{base,unit}})',
            r'D': r'Load damping constant (% change in load / % change in frequency)',
          },
        ),
        FormulaItem(
          name: 'Steady-State Frequency Deviation (Δf)',
          tex: r'\Delta f_{ss} = -\frac{\Delta P_L}{\beta_{\text{sys}}} \quad (\text{pu}), \quad \Delta f_{\text{Hz}} = \Delta f_{ss} \times f_0',
          explanation:
              'Steady-state frequency drop resulting from a step increase in electrical load ΔP_L.',
        ),
        FormulaItem(
          name: 'Individual Generator Governor Power Pickup',
          tex: r'\Delta P_{mi} = -\frac{\Delta f_{ss}}{R_{i,\text{sys}}} \quad (\text{pu}), \quad \Delta P_{mi,\text{MW}} = \Delta P_{mi} \times S_{\text{base,sys}}',
          explanation:
              'Proportionate power picked up by unit i in response to grid frequency deviation.',
        ),
        FormulaItem(
          name: 'Two-Area Tie-Line Power Flow Deviation',
          tex: r'\Delta P_{\text{tie}1} = -\Delta P_{\text{tie}2} = \frac{\Delta P_{L2}\beta_1 - \Delta P_{L1}\beta_2}{\beta_1 + \beta_2}',
          explanation:
              'Inter-area power transfer through the tie-line connecting control Area 1 and Area 2.',
        ),
        FormulaItem(
          name: 'Area Control Error (ACE)',
          tex: r'\text{ACE}_i = \Delta P_{\text{tie},i} + B_i \Delta f',
          explanation:
              'Control signal used by secondary Automatic Generation Control (AGC) with frequency bias B_i to restore frequency and net interchange to scheduled values.',
        ),
      ],
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final filteredCategories = _categories.map((cat) {
      if (_searchQuery.isEmpty) return cat;
      final q = _searchQuery.toLowerCase();
      final matchingItems = cat.items.where((item) {
        return item.name.toLowerCase().contains(q) ||
            item.explanation.toLowerCase().contains(q) ||
            item.tex.toLowerCase().contains(q);
      }).toList();

      return FormulaCategory(
        title: cat.title,
        description: cat.description,
        items: matchingItems,
      );
    }).where((cat) => cat.items.isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Formula Reference Sheet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('EE4530: Power System Analysis & Control', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        elevation: 1,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: isDark ? Colors.grey.shade900 : Colors.blueGrey.shade50,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search formulas (e.g., Jacobian, Y_bus, Gauss, Line flow)...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark ? Colors.grey.shade800 : Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.trim();
                });
              },
            ),
          ),
          Expanded(
            child: filteredCategories.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 48, color: Colors.grey.shade500),
                        const SizedBox(height: 12),
                        Text('No formulas matched "$_searchQuery"', style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredCategories.length,
                    itemBuilder: (context, catIndex) {
                      final cat = filteredCategories[catIndex];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    cat.title,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 12, bottom: 12),
                            child: Text(
                              cat.description,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                              ),
                            ),
                          ),
                          ...cat.items.map((item) => _buildFormulaCard(context, item, isDark)),
                          const SizedBox(height: 16),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormulaCard(BuildContext context, FormulaItem item, bool isDark) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.black38 : const Color(0xFFF7F9FC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.blueGrey.shade100,
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Math.tex(
                  item.tex,
                  mathStyle: MathStyle.display,
                  textStyle: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.lightBlue.shade200 : const Color(0xFF0F3A66),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              item.explanation,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
              ),
            ),
            if (item.variables.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: item.variables.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Math.tex(
                            entry.key,
                            textStyle: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              ': ${entry.value}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
