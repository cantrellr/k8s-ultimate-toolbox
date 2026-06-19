## Description

<!-- Describe your changes in detail -->

## Related Issue

<!-- Link to the issue this PR addresses (if applicable) -->

Fixes #

## Type of Change

<!-- Mark the relevant option with an [x] -->

- [ ] 🐛 Bug fix (non-breaking change that fixes an issue)
- [ ] ✨ New feature (non-breaking change that adds functionality)
- [ ] 🔧 New tool (adds a new tool to the toolbox)
- [ ] 📝 Documentation update
- [ ] 🔨 Refactoring (no functional changes)
- [ ] ⚠️ Breaking change (fix or feature that would cause existing functionality to change)

## Checklist

<!-- Mark completed items with an [x] -->

### General
- [ ] My code follows the project's style guidelines
- [ ] I have performed a self-review of my changes
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] My changes generate no new warnings

### If Adding/Modifying Tools (Dockerfile)
- [ ] Tool is added in the appropriate categorized section
- [ ] Tool has a comment explaining its purpose
- [ ] Version is pinned where possible
- [ ] Tool works on both amd64 and arm64 (or documented if not)
- [ ] Package manager cache is cleaned after installation

### If Modifying Helm Chart
- [ ] values.yaml is updated with new configuration options
- [ ] Default values are sensible and secure
- [ ] Template changes are tested with `helm template`

### Documentation
- [ ] I have updated relevant documentation
- [ ] TOOLS-REFERENCE.md is updated (if adding tools)
- [ ] README.md tool count is updated (if adding tools)
- [ ] Examples are provided for new features

### Testing
- [ ] I have tested my changes locally
- [ ] Existing tests pass (`make test`)
- [ ] New tests added for new functionality (if applicable)

## Screenshots/Logs

<!-- If applicable, add screenshots or logs to help explain your changes -->

## Additional Notes

<!-- Any additional information that reviewers should know -->
