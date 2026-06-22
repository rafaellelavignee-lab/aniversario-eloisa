-- ================================================================
-- 15 Anos da Eloisa — Setup Completo do Banco de Dados
-- Execute no Supabase > SQL Editor (em ordem, de cima para baixo)
-- ================================================================

-- ════════════════════════════════════════════════════
-- EXTENSÕES
-- ════════════════════════════════════════════════════
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ════════════════════════════════════════════════════
-- TABELAS
-- ════════════════════════════════════════════════════

-- 1. Configurações da festa (1 única linha)
CREATE TABLE IF NOT EXISTS configuracoes (
  id                 INTEGER      PRIMARY KEY DEFAULT 1,
  data_festa         DATE,
  local_festa        TEXT,
  horario            TEXT,
  tema               TEXT,
  mensagem_especial  TEXT,
  foto_principal_url TEXT,
  atualizado_em      TIMESTAMPTZ  DEFAULT NOW()
);
INSERT INTO configuracoes (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- 2. Perfis de usuários (espelho do Supabase Auth)
CREATE TABLE IF NOT EXISTS usuarios (
  id         UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nome       TEXT        NOT NULL,
  email      TEXT        NOT NULL UNIQUE,
  tipo       TEXT        NOT NULL DEFAULT 'colaborador'
                         CHECK (tipo IN ('admin','colaborador')),
  criado_em  TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Convidados
CREATE TABLE IF NOT EXISTS convidados (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  nome           TEXT        NOT NULL,
  status         TEXT        DEFAULT 'aguardando'
                             CHECK (status IN ('confirmado','aguardando','cancelado')),
  criado_por     TEXT,
  criado_por_id  UUID        REFERENCES auth.users(id),
  criado_em      TIMESTAMPTZ DEFAULT NOW(),
  token_rsvp     TEXT        UNIQUE DEFAULT encode(gen_random_bytes(16),'hex'),
  resposta_rsvp  TEXT        CHECK (resposta_rsvp IN ('confirmado','recusado') OR resposta_rsvp IS NULL),
  data_resposta  TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_convidados_token  ON convidados(token_rsvp);
CREATE INDEX IF NOT EXISTS idx_convidados_status ON convidados(status);
CREATE INDEX IF NOT EXISTS idx_convidados_criado ON convidados(criado_por_id);

-- 4. Checklists (food / decor / music / looks / vendors / tasks)
CREATE TABLE IF NOT EXISTS checklists (
  id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo      TEXT        NOT NULL CHECK (tipo IN ('food','decor','music','looks','vendors','tasks')),
  texto     TEXT        NOT NULL,
  concluido BOOLEAN     DEFAULT FALSE,
  criado_em TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_checklists_tipo ON checklists(tipo);

-- 5. Orçamentos
CREATE TABLE IF NOT EXISTS orcamentos (
  id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  nome        TEXT          NOT NULL,
  valor       NUMERIC(12,2) NOT NULL DEFAULT 0,
  categoria   TEXT          DEFAULT 'Geral',
  responsavel TEXT,
  status      TEXT          DEFAULT 'pendente' CHECK (status IN ('pendente','pago')),
  criado_em   TIMESTAMPTZ   DEFAULT NOW()
);

-- 6. Presentes / Lista de desejo
CREATE TABLE IF NOT EXISTS presentes (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  nome          TEXT        NOT NULL,
  descricao     TEXT,
  imagem_url    TEXT,
  link_compra   TEXT,
  reservado     BOOLEAN     DEFAULT FALSE,
  reservado_por TEXT,
  criado_em     TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Fotos
CREATE TABLE IF NOT EXISTS fotos (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  titulo       TEXT,
  legenda      TEXT,
  url          TEXT        NOT NULL,
  bucket       TEXT        DEFAULT 'fotos-publicas',
  visibilidade TEXT        DEFAULT 'public' CHECK (visibilidade IN ('public','private')),
  criado_por   UUID        REFERENCES auth.users(id),
  criado_em    TIMESTAMPTZ DEFAULT NOW()
);

-- 8. Notas (1 única linha)
CREATE TABLE IF NOT EXISTS notas (
  id            INTEGER     PRIMARY KEY DEFAULT 1,
  conteudo      TEXT        DEFAULT '',
  atualizado_em TIMESTAMPTZ DEFAULT NOW()
);
INSERT INTO notas (id, conteudo) VALUES (1,'') ON CONFLICT (id) DO NOTHING;

-- 9. Playlist (1 única linha)
CREATE TABLE IF NOT EXISTS playlist (
  id            INTEGER     PRIMARY KEY DEFAULT 1,
  spotify       TEXT        DEFAULT '',
  youtube       TEXT        DEFAULT '',
  deezer        TEXT        DEFAULT '',
  atualizado_em TIMESTAMPTZ DEFAULT NOW()
);
INSERT INTO playlist (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- ════════════════════════════════════════════════════
-- FUNÇÕES AUXILIARES
-- ════════════════════════════════════════════════════

-- Retorna o tipo do usuário autenticado
CREATE OR REPLACE FUNCTION get_user_tipo(uid UUID)
RETURNS TEXT AS $$
  SELECT tipo FROM public.usuarios WHERE id = uid;
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- Responde RSVP via token (sem autenticação)
CREATE OR REPLACE FUNCTION responder_rsvp(p_token TEXT, p_resposta TEXT)
RETURNS BOOLEAN AS $$
DECLARE updated INT;
BEGIN
  UPDATE public.convidados
  SET
    resposta_rsvp = p_resposta,
    data_resposta = NOW(),
    status        = CASE WHEN p_resposta='confirmado' THEN 'confirmado' ELSE 'cancelado' END
  WHERE token_rsvp = p_token
    AND (resposta_rsvp IS NULL OR resposta_rsvp != p_resposta);
  GET DIAGNOSTICS updated = ROW_COUNT;
  RETURN updated > 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Reserva um presente via token (sem autenticação)
CREATE OR REPLACE FUNCTION reservar_presente(p_id UUID, p_nome TEXT)
RETURNS BOOLEAN AS $$
DECLARE updated INT;
BEGIN
  UPDATE public.presentes
  SET reservado=TRUE, reservado_por=p_nome
  WHERE id=p_id AND reservado=FALSE;
  GET DIAGNOSTICS updated = ROW_COUNT;
  RETURN updated > 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════
-- TRIGGER: criar perfil ao registrar novo usuário
-- ════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.usuarios (id, nome, email, tipo)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'nome', split_part(NEW.email,'@',1)),
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'tipo','colaborador')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ════════════════════════════════════════════════════
ALTER TABLE configuracoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuarios      ENABLE ROW LEVEL SECURITY;
ALTER TABLE convidados    ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklists    ENABLE ROW LEVEL SECURITY;
ALTER TABLE orcamentos    ENABLE ROW LEVEL SECURITY;
ALTER TABLE presentes     ENABLE ROW LEVEL SECURITY;
ALTER TABLE fotos         ENABLE ROW LEVEL SECURITY;
ALTER TABLE notas         ENABLE ROW LEVEL SECURITY;
ALTER TABLE playlist      ENABLE ROW LEVEL SECURITY;

-- Limpa políticas antigas antes de criar
DO $$ DECLARE r RECORD; BEGIN
  FOR r IN SELECT policyname, tablename FROM pg_policies WHERE schemaname='public' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', r.policyname, r.tablename);
  END LOOP;
END $$;

-- CONFIGURACOES: público lê, admin escreve
CREATE POLICY "cfg_read"  ON configuracoes FOR SELECT USING (true);
CREATE POLICY "cfg_write" ON configuracoes FOR ALL    USING (get_user_tipo(auth.uid())='admin');

-- USUARIOS: autenticados leem, admin gerencia
CREATE POLICY "usr_read"   ON usuarios FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "usr_insert" ON usuarios FOR INSERT WITH CHECK (get_user_tipo(auth.uid())='admin');
CREATE POLICY "usr_update" ON usuarios FOR UPDATE USING (get_user_tipo(auth.uid())='admin');
CREATE POLICY "usr_delete" ON usuarios FOR DELETE USING (get_user_tipo(auth.uid())='admin');

-- CONVIDADOS: autenticados gerenciam; RPC pública lida via função SECURITY DEFINER
CREATE POLICY "cnv_read"   ON convidados FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "cnv_insert" ON convidados FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "cnv_update" ON convidados FOR UPDATE USING (auth.uid() IS NOT NULL);
CREATE POLICY "cnv_delete" ON convidados FOR DELETE USING (get_user_tipo(auth.uid())='admin');
-- Leitura pública por token (para rsvp.html e convite.html)
CREATE POLICY "cnv_token_read" ON convidados FOR SELECT USING (token_rsvp IS NOT NULL);

-- CHECKLISTS: apenas autenticados
CREATE POLICY "ckl_all" ON checklists FOR ALL USING (auth.uid() IS NOT NULL);

-- ORCAMENTOS: apenas autenticados
CREATE POLICY "orc_all" ON orcamentos FOR ALL USING (auth.uid() IS NOT NULL);

-- PRESENTES: público lê, admin escreve (reserva via RPC)
CREATE POLICY "prs_read"   ON presentes FOR SELECT USING (true);
CREATE POLICY "prs_insert" ON presentes FOR INSERT WITH CHECK (get_user_tipo(auth.uid())='admin');
CREATE POLICY "prs_update" ON presentes FOR UPDATE USING (get_user_tipo(auth.uid())='admin');
CREATE POLICY "prs_delete" ON presentes FOR DELETE USING (get_user_tipo(auth.uid())='admin');

-- FOTOS: público vê públicas; autenticados veem tudo
CREATE POLICY "fot_read"   ON fotos FOR SELECT USING (visibilidade='public' OR auth.uid() IS NOT NULL);
CREATE POLICY "fot_insert" ON fotos FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "fot_update" ON fotos FOR UPDATE USING (get_user_tipo(auth.uid())='admin');
CREATE POLICY "fot_delete" ON fotos FOR DELETE USING (get_user_tipo(auth.uid())='admin');

-- NOTAS e PLAYLIST: autenticados escrevem, público lê playlist
CREATE POLICY "not_all"     ON notas    FOR ALL    USING (auth.uid() IS NOT NULL);
CREATE POLICY "pla_read"    ON playlist FOR SELECT USING (true);
CREATE POLICY "pla_write"   ON playlist FOR ALL    USING (auth.uid() IS NOT NULL);

-- ════════════════════════════════════════════════════
-- STORAGE — Buckets e Políticas
-- (Execute separado se der erro de permissão)
-- ════════════════════════════════════════════════════

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('fotos-publicas',  'fotos-publicas',  true,  5242880, ARRAY['image/jpeg','image/png','image/webp','image/gif']),
  ('fotos-privadas',  'fotos-privadas',  false, 5242880, ARRAY['image/jpeg','image/png','image/webp','image/gif']),
  ('presentes',       'presentes',       true,  3145728, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO NOTHING;

-- fotos-publicas
CREATE POLICY "fps_read"   ON storage.objects FOR SELECT USING (bucket_id='fotos-publicas');
CREATE POLICY "fps_write"  ON storage.objects FOR INSERT WITH CHECK (bucket_id='fotos-publicas' AND auth.uid() IS NOT NULL);
CREATE POLICY "fps_delete" ON storage.objects FOR DELETE USING (bucket_id='fotos-publicas' AND get_user_tipo(auth.uid())='admin');

-- fotos-privadas
CREATE POLICY "fpr_read"   ON storage.objects FOR SELECT USING (bucket_id='fotos-privadas' AND auth.uid() IS NOT NULL);
CREATE POLICY "fpr_write"  ON storage.objects FOR INSERT WITH CHECK (bucket_id='fotos-privadas' AND auth.uid() IS NOT NULL);
CREATE POLICY "fpr_delete" ON storage.objects FOR DELETE USING (bucket_id='fotos-privadas' AND get_user_tipo(auth.uid())='admin');

-- presentes
CREATE POLICY "pre_read"   ON storage.objects FOR SELECT USING (bucket_id='presentes');
CREATE POLICY "pre_write"  ON storage.objects FOR INSERT WITH CHECK (bucket_id='presentes' AND get_user_tipo(auth.uid())='admin');
CREATE POLICY "pre_delete" ON storage.objects FOR DELETE USING (bucket_id='presentes' AND get_user_tipo(auth.uid())='admin');
