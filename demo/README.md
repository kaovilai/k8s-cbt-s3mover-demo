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
- **Velero Status**: CBT and block data mover behavior as of 2026-10-27, including the Ceph RBD Case 2 fallback in 1.19.0

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

### Checking for cut-off slides

Slidev renders every slide on a fixed 980x552 canvas and then scales it to the
viewport. That means a slide can look fine in the overview while its right or
bottom edge is still being cut off for the audience. Diagrams are the usual
culprit: a wide mermaid graph overflows its column and loses boxes off the edge.

Run the overflow check before pushing:

```bash
npm run dev            # in one terminal
npm run check:overflow # in another
```

It walks every slide, compares each element (including mermaid diagrams drawn
inside a shadow root) against that slide's own canvas, and fails with the slide
number, the offending element, and how far past the edge it sits. Point it at a
different port with `npm run check:overflow -- --url http://localhost:3031`, or
check a subset with `--pages 11,17-20`.

The `Check slide overflow` job runs the same script on every push to `main` and
blocks deployment when a slide no longer fits.

### Keeping the Velero status current

The Velero/Ceph section is the part of this deck that goes stale fastest. A weekly
scheduled check re-reads the upstream items below, compares them against what
`slides.md` and the top-level `README.md` claim, and reports the file and line that
needs editing. It reports only; it never commits or opens a PR.

| Source | What it settles |
|---|---|
| [kubernetes/enhancements#6479](https://github.com/kubernetes/enhancements/pull/6479) | whether KEP-3314 documents `requireBaseSnapshotForDelta` |
| [external-snapshot-metadata#258](https://github.com/kubernetes-csi/external-snapshot-metadata/pull/258) | whether that CRD field is in a release yet |
| [ceph-csi#6680](https://github.com/ceph/ceph-csi/issues/6680) | whether RBD advertises the field |
| [ceph-csi#6679](https://github.com/ceph/ceph-csi/issues/6679) | SELinux host mount, fixed by `enableSelinuxHostMount` |
| [velero#10743](https://github.com/velero-io/velero/issues/10743), [velero#10744](https://github.com/velero-io/velero/issues/10744) | the Case 2 retention design |
| [velero#10722](https://github.com/velero-io/velero/issues/10722) | Velero reading the driver flag |
| [rook#18636](https://github.com/rook/rook/pull/18636), [ceph-csi-operator#649](https://github.com/ceph/ceph-csi-operator/pull/649) | the OpenShift install fixes |

To run the same comparison by hand:

```bash
gh pr view 6479 --repo kubernetes/enhancements --json state,mergedAt
gh pr view 258 --repo kubernetes-csi/external-snapshot-metadata --json state
gh release list --repo kubernetes-csi/external-snapshot-metadata --limit 5
gh issue view 10743 --repo velero-io/velero --json state
gh release list --repo velero-io/velero --limit 5
```

Update the top-level `README.md` Velero section first, then mirror the wording into
the deck so the long-form rationale and the slides do not drift apart.

Two causes worth knowing about, because both look like a color/contrast problem
rather than a layout one:

- Mermaid diagrams render into a shadow root, so page CSS cannot resize them.
  Set the diagram's own `scale` and pick a direction (`graph TB` rather than
  `graph LR`) that fits the column.
- The default theme applies `opacity: 0.5` to a paragraph that follows an `h1`,
  treating it as a subtitle. If that line must read at full strength, add
  `!opacity-100`.

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
- **Documentation**: `../README.md`

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
