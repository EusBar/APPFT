/// Projeto Supabase do FINTRACK.
///
/// A chave "publishable" é pública por natureza (vai dentro de qualquer app):
/// sozinha não dá acesso a nada. Cada pedido de dados exige a sessão do
/// utilizador, e as regras Row Level Security só deixam ver as suas linhas.
/// A chave secreta do servidor nunca entra no app.
class CloudConfig {
  static const url = 'https://ombecebntvsidifctjts.supabase.co';
  static const publishableKey = 'sb_publishable_-x9xNkrPvd6BhK4_I0hW0A_tnY31hfb';
}
