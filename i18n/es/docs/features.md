<!-- source: docs/features.md sha256:1184b77dc92e9620543dd97b37cdc7008e99ad96961ea016f6267e81bee7510c -->

# Funcionalidades

[English](../../../docs/features.md) · [Português (Brasil)](../../pt-BR/docs/features.md) · Español

## Qué obtienes

- **Reglas** para el agente: una página que vale en toda sesión (`AGENTS.md`) y reglas por tema (git, seguridad,
  calidad, documentación, frontend, infraestructura, modelos, revisión), que se leen cuando el tema aparece.
- **Skills**: comandos de barra para el flujo diario (`/merge`, `/commit`, `/push`, `/validate`, `/draft-prompt`,
  `/prompt`, `/pilot`, `/local-env`, `/normalize-projects`).
- **Agentes**: subagentes para requisitos, arquitectura, implementación, pruebas, revisión, verificación,
  infraestructura, scripts, documentación e investigación, cada uno con su modelo y su effort.
- **Hooks** que retienen solo lo que nunca debe ocurrir sin ti: escrituras git fuera del gate, cambios en la nube,
  borrado de bases de datos, secretos en un commit. [Hooks que se ejecutan en tu máquina](hooks.md) los enumera todos.
- **Un gate de merge**: el trabajo ocurre en un clon dentro de `tmp/work/`, y `/merge` lo lleva a la rama `developer`
  del proyecto después de la suite de pruebas completa, las validaciones, un escaneo de secretos y una revisión contra
  tu pedido.
- **Una capa custom**: tu propio repositorio git privado en `custom/`, para tu empresa, tu nube, tu identidad visual,
  la lista de proyectos, los pedidos y las lecciones. Nunca entra en este repositorio.
- **Herramientas**: un Grafana local para la telemetría de Claude Code, una consola de contenedores (Docker CE en
  Linux, Colima en macOS), simuladores de login y de Safe Browsing, una consola de Azurite, un informe de uso y una
  alerta de modelo. Cada una tiene su README en `workspace/tools/`.

## La capa custom

`custom/` es **tu** repositorio git privado, separado del producto, y el único lugar para lo que es tuyo: nombre y
grafía de la empresa, nube y tenant, identidad visual, la lista de tus proyectos, los pedidos escritos, las lecciones,
los `.env` completados (`custom/env/`, siempre ignorados por git) y el registro de prompts. El workspace funciona sin
ella y pregunta, cuando lo necesita, la nube, la identidad visual y la carpeta de cada proyecto. Nunca entra en un pull
request a este repositorio.
