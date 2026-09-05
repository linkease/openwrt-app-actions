const stateByElement = new WeakMap();

function normalizeBasePath(path) {
  const value =
    typeof path === "string" && path.trim() ? path.trim() : "/apps/agentflow/";
  return value.endsWith("/") ? value : `${value}/`;
}

export async function bootstrap() {}

export async function mount(props) {
  const root = props && props.domElement;
  if (!root) {
    return;
  }

  const basePath = normalizeBasePath(props.context && props.context.basePath);
  root.innerHTML = `
    <style>
      :host {
        display: block;
        width: 100%;
        height: 100%;
      }

      .agentflow-frame {
        display: block;
        width: 100%;
        height: 100%;
        min-height: 620px;
        border: 0;
        background: #f6f7f9;
      }
    </style>
    <iframe
      class="agentflow-frame"
      src="${basePath}"
      title="AgentFlow"
      loading="eager"
      referrerpolicy="same-origin"
    ></iframe>
  `;

  stateByElement.set(root, { basePath });
}

export async function unmount(props) {
  const root = props && props.domElement;
  if (!root) {
    return;
  }
  stateByElement.delete(root);
  root.innerHTML = "";
}
