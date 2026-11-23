# mac_minimal_monitor

Aplicativo minimalista e nativo para a barra de status do macOS escrito em Swift (SwiftUI + AppKit, sem dependências externas) para acompanhar em tempo real o consumo de **memória RAM** e o uso da **CPU**.

## Recursos

- **Barra de status compacta**: exibe ícone + memória RAM consumida (ex.: `5.3 GB`) e ícone + resumo de uso da CPU (ex.: `12%`), com largura estabilizada e alerta visual em laranja/vermelho em uso alto.
- **Modo monocromático opcional**: alterne entre badges coloridos ou ícones monocromáticos nativos adaptados ao modo claro/escuro do macOS.
- **Popover detalhado**:
  - **Memória RAM** (compatível com o Monitor de Atividade do macOS): Apps, Wired, Comprimida, Cache, Livre e Swap.
  - **CPU**: resumo geral (Usuário, Sistema, Ocioso), uso individual por núcleo e carga média (`1 / 5 / 15 min`).
  - Seletor de intervalo de atualização (`1s`, `2s`, `5s`).
  - Opção de iniciar junto com a sessão (`SMAppService`) e atalho para o Monitor de Atividade.
- **Sem ícone no Dock** (`LSUIElement = true`) e baixo consumo de recursos.

## Requisitos

- macOS 13.0 ou superior
- Swift 5.9+ (Xcode ou Command Line Tools)

## Compilar e instalar

```zsh
./build.sh
```

O script compila em modo `release`, monta e assina o bundle `Resources Monitor.app` na raiz do projeto.

Para abrir diretamente:

```zsh
open "Resources Monitor.app"
```

Para instalar em `/Applications`:

```zsh
cp -R "Resources Monitor.app" /Applications/ && open "/Applications/Resources Monitor.app"
```

## Licença

[MIT](LICENSE)
