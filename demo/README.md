# K8s CBT S3Mover Demo Presentation

A comprehensive Slidev presentation showcasing the Kubernetes Changed Block Tracking (CBT) demo with S3 storage integration.

## Overview

This presentation covers:

- **KEP-3314**: Changed Block Tracking API for Kubernetes
- **Architecture**: CSI SnapshotMetadata Service, CRDs, and sidecars
- **Demo Workflow**: Complete walkthrough of the demo implementation
- **Use Cases**: Full and incremental snapshot backups
- **Security Model**: Authentication, authorization, and transport encryption
- **CI/CD Pipeline**: Automated testing and validation

## Prerequisites

```bash
# Install Node.js (v18 or higher)
# Install npm dependencies
npm install
```

## Running the Presentation

### Development Mode

Start the presentation in development mode with hot reload:

```bash
npm run dev
```

Then open your browser at `http://localhost:3030`

### Build for Production

Build the presentation as a static site:

```bash
npm run build
```

The built files will be in the `dist/` directory.

### Export to PDF

Export the presentation to PDF:

```bash
npm run export
```

### GitHub Pages Deployment

The presentation is automatically deployed to GitHub Pages whenever changes are pushed:

- **Trigger**: Push to `main` branch with changes to `demo/` files
- **Workflow**: `.github/workflows/build-presentation.yaml`
- **URL**: `https://<username>.github.io/<repo-name>/`
- **Technology**: Uses @antfu/ni for package management

To manually trigger a deployment, use the GitHub Actions "Deploy pages" workflow with the "Run workflow" button.

#### Setup GitHub Pages

1. Go to repository **Settings** → **Pages**
2. Set **Source** to "GitHub Actions"
3. The presentation will be automatically deployed on the next push to `main`

The `dist/` directory is generated during the workflow and is **not** tracked in git.

## Presentation Structure

1. **Title Slide**: Introduction to K8s CBT S3Mover Demo
2. **Overview**: What is CBT (KEP-3314) and key benefits
3. **CBT API Architecture**: Three key components and security model
4. **Demo Architecture**: Components diagram and architecture
5. **Demo Workflow**: Phase 1 (Setup) and Phase 2 (Deploy)
6. **Creating Snapshots**: Initial and delta snapshots
7. **Use Cases**: Full and incremental backup workflows
8. **CBT API Usage**: Before and after PR #180 approaches
9. **Build Tools**: Backup and restore tool information
10. **Data Integrity**: Verification process and results
11. **Troubleshooting**: Common issues and solutions
12. **CI/CD Pipeline**: Workflow jobs and triggers
13. **Demo Results**: What was demonstrated
14. **Try It Yourself**: Quick start guide
15. **Official Resources**: Kubernetes docs and references
16. **Thank You**: Closing slide

## Slidev Features Used

- **Mermaid Diagrams**: Visual architecture and flow diagrams
- **Code Highlighting**: Syntax-highlighted YAML, Bash, and SQL
- **Progressive Clicks**: Step-by-step content revelation
- **Layouts**: Various layouts (two-cols, center, default)
- **Transitions**: Smooth slide transitions
- **Themes**: Default theme with custom styling

## Official References

### Kubernetes Documentation

- [KEP-3314: CSI Changed Block Tracking](https://github.com/kubernetes/enhancements/tree/master/keps/sig-storage/3314-csi-changed-block-tracking)
- [CSI Developer Documentation](https://kubernetes-csi.github.io/docs/external-snapshot-metadata.html)
- [Kubernetes Blog Post](https://github.com/kubernetes/website/pull/48456) (upcoming)

### Implementation References

- [external-snapshot-metadata](https://github.com/kubernetes-csi/external-snapshot-metadata) repository
- [schema.proto](https://github.com/kubernetes-csi/external-snapshot-metadata/blob/main/proto/schema.proto) - gRPC API definitions
- [snapshot-metadata-lister](https://github.com/kubernetes-csi/external-snapshot-metadata/tree/main/examples/snapshot-metadata-lister) example
- [csi-hostpath-driver](https://github.com/kubernetes-csi/csi-driver-host-path) with CBT support

## Demo Repository

For the actual demo implementation, see:

- **Scripts**: `../scripts/` directory
- **Tools**: `../tools/cbt-backup/`
- **Workflow**: `../.github/workflows/demo.yaml`
- **Documentation**: `../README.md`, `../STATUS.md`

## Customization

To customize the presentation:

1. **Edit slides**: Modify `slides.md`
2. **Change theme**: Update the `theme` in the frontmatter
3. **Add images**: Place images in the project and reference them
4. **Modify styling**: Add custom CSS in the slides or separate file

## Tips for Presenting

- Use **Space** or **Arrow keys** to navigate
- Press **?** to see keyboard shortcuts
- Press **o** for slide overview
- Press **d** for dark mode
- Use presenter notes (only visible in presenter mode)

## Learn More

- [Slidev Documentation](https://sli.dev)
- [Slidev GitHub](https://github.com/slidevjs/slidev)
- [Syntax Guide](https://github.com/slidevjs/slidev/blob/main/docs/guide/syntax.md)
