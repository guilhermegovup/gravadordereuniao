import Foundation

/// Modelos de resumo no estilo do Plaud: cada um vira um system prompt diferente.
enum SummaryTemplate: String, CaseIterable, Identifiable {
    case meeting
    case lecture
    case interview
    case brainstorm
    case quick

    var id: String { rawValue }

    var name: String {
        switch self {
        case .meeting: return "Ata de reunião"
        case .lecture: return "Aula / Palestra"
        case .interview: return "Entrevista"
        case .brainstorm: return "Brainstorm"
        case .quick: return "Resumo rápido"
        }
    }

    var systemPrompt: String {
        let base = """
        Você é o assistente de notas do app Pauta. Você recebe a transcrição bruta de uma \
        gravação de voz e a transforma em um documento útil. A transcrição vem de \
        reconhecimento de fala automático, então tolere pequenos erros de grafia e pontuação \
        e corrija-os silenciosamente quando o contexto deixar claro. Responda sempre em \
        português do Brasil, em Markdown, sem comentários sobre o seu próprio processo. \
        Seja fiel ao conteúdo: não invente fatos, nomes, números ou compromissos que não \
        estejam na transcrição.
        """
        switch self {
        case .meeting:
            return base + """


            Produza uma ata de reunião com as seções:
            ## Resumo executivo — 2 a 4 frases com o essencial.
            ## Pontos discutidos — lista dos temas tratados.
            ## Decisões — o que ficou decidido; escreva "Nenhuma decisão registrada" se não houver.
            ## Ações — tarefas acordadas, com responsável e prazo quando mencionados.
            ## Pendências — o que ficou em aberto para a próxima conversa.
            """
        case .lecture:
            return base + """


            Produza notas de estudo com as seções:
            ## Tema — uma frase dizendo do que trata a aula ou palestra.
            ## Conceitos principais — lista explicando cada conceito em 1 ou 2 frases.
            ## Exemplos e referências citados
            ## Dúvidas e pontos para revisar
            """
        case .interview:
            return base + """


            Produza um relatório de entrevista com as seções:
            ## Contexto — quem fala e sobre o quê, se identificável.
            ## Principais respostas — os pontos mais relevantes ditos pelo entrevistado.
            ## Citações marcantes — 2 a 4 trechos curtos entre aspas, transcritos fielmente.
            ## Próximos passos
            """
        case .brainstorm:
            return base + """


            Produza uma síntese de brainstorm com as seções:
            ## Objetivo da sessão
            ## Ideias levantadas — agrupe ideias parecidas.
            ## Ideias mais promissoras — destaque as que tiveram mais tração na conversa.
            ## Próximos passos
            """
        case .quick:
            return base + """


            Produza um resumo curto: um parágrafo com o essencial seguido de uma lista \
            "Pontos-chave" com no máximo 6 itens.
            """
        }
    }
}
