/// Natureza de uma categoria: só entradas ou só saídas.
enum CategoryKind {
  income('income'),
  expense('expense');

  const CategoryKind(this.code);
  final String code;

  static CategoryKind fromCode(String code) => values.firstWhere(
        (k) => k.code == code,
        orElse: () => throw ArgumentError.value(code, 'code', 'Natureza desconhecida'),
      );
}

/// Categoria de movimentos (secção 7).
class Category {
  const Category({
    required this.id,
    required this.kind,
    required this.name,
    required this.icon,
    this.archived = false,
  });

  final String id;
  final CategoryKind kind;
  final String name;

  /// Nome simbólico do ícone; a interface traduz para um desenho.
  final String icon;
  final bool archived;

  /// Categorias iniciais. Os identificadores são estáveis: nunca mudar.
  static const defaults = <Category>[
    Category(id: 'exp.habitacao', kind: CategoryKind.expense, name: 'Habitação', icon: 'home'),
    Category(id: 'exp.alimentacao', kind: CategoryKind.expense, name: 'Alimentação', icon: 'food'),
    Category(id: 'exp.transporte', kind: CategoryKind.expense, name: 'Transporte', icon: 'transport'),
    Category(id: 'exp.saude', kind: CategoryKind.expense, name: 'Saúde', icon: 'health'),
    Category(id: 'exp.educacao', kind: CategoryKind.expense, name: 'Educação', icon: 'education'),
    Category(id: 'exp.pessoais', kind: CategoryKind.expense, name: 'Despesas pessoais', icon: 'personal'),
    Category(id: 'exp.domesticas', kind: CategoryKind.expense, name: 'Despesas domésticas', icon: 'household'),
    Category(id: 'exp.dividas', kind: CategoryKind.expense, name: 'Empréstimos e dívidas', icon: 'debt'),
    Category(id: 'exp.poupanca', kind: CategoryKind.expense, name: 'Poupança', icon: 'savings'),
    Category(id: 'exp.emergencia', kind: CategoryKind.expense, name: 'Reserva de emergência', icon: 'shield'),
    Category(id: 'exp.projetos', kind: CategoryKind.expense, name: 'Projetos', icon: 'project'),
    Category(id: 'exp.familia', kind: CategoryKind.expense, name: 'Família e apoio', icon: 'family'),
    Category(id: 'exp.kixikila', kind: CategoryKind.expense, name: 'Kixikila', icon: 'group'),
    Category(id: 'exp.outros', kind: CategoryKind.expense, name: 'Outros', icon: 'other'),
    Category(id: 'inc.salario', kind: CategoryKind.income, name: 'Salário', icon: 'salary'),
    Category(id: 'inc.negocio', kind: CategoryKind.income, name: 'Negócio e vendas', icon: 'business'),
    Category(id: 'inc.rendas', kind: CategoryKind.income, name: 'Rendas', icon: 'home'),
    Category(id: 'inc.apoio', kind: CategoryKind.income, name: 'Apoio familiar e ofertas', icon: 'family'),
    Category(id: 'inc.reembolsos', kind: CategoryKind.income, name: 'Reembolsos', icon: 'refund'),
    Category(id: 'inc.juros', kind: CategoryKind.income, name: 'Juros e rendimentos', icon: 'interest'),
    Category(id: 'inc.kixikila', kind: CategoryKind.income, name: 'Kixikila', icon: 'group'),
    Category(id: 'inc.outros', kind: CategoryKind.income, name: 'Outros', icon: 'other'),
  ];
}
