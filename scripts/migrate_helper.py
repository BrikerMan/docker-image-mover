#!/usr/bin/env python3
"""
MigrateHelper - A helper class for Docker image migration tasks.
Helps with extracting and transforming Docker images in compose files.
"""

import os
import re
import yaml
from typing import List, Dict, Optional
from pathlib import Path


class MigrateHelper:
    """Helper class for Docker image migration tasks."""

    def __init__(self):
        self.image_pattern = re.compile(r'^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*(?::[a-z0-9]+(?:[._-][a-z0-9]+)*)?$')

    def _is_valid_image(self, image: str) -> bool:
        """Check if the string is a valid docker image name."""
        return bool(self.image_pattern.match(image.lower()))

    def _extract_image_name(self, image: str) -> str:
        """Extract the last part of the image name."""
        # Split by ':' first to separate tag
        name_parts = image.split(':')[0]
        # Get the last part after '/'
        return name_parts.split('/')[-1]

    def _transform_image(self, image: str, new_registry: str) -> str:
        """Transform image name according to migration rules."""
        if not image:
            return image
            
        # Split image name and tag
        parts = image.split(':')
        image_name = self._extract_image_name(parts[0])
        tag = parts[1] if len(parts) > 1 else 'latest'
        
        # Create new image name
        return f"{new_registry}/{image_name}:{tag}"

    def extract_images(self, yaml_file: str) -> List[str]:
        """
        Extract all Docker images from a YAML file (e.g., docker-compose.yml).
        
        Args:
            yaml_file: Path to the YAML file
            
        Returns:
            List of image names in alphabetical order
        """
        if not os.path.exists(yaml_file):
            raise FileNotFoundError(f"File not found: {yaml_file}")
            
        with open(yaml_file, 'r') as f:
            try:
                compose_data = yaml.safe_load(f)
            except yaml.YAMLError as e:
                raise ValueError(f"Invalid YAML file: {e}")

        images = set()
        
        # Handle both v1 and v2+ compose file formats
        services = compose_data.get('services', compose_data)
        
        if not isinstance(services, dict):
            raise ValueError("Invalid compose file format")
            
        for service in services.values():
            if isinstance(service, dict):
                # Get image from 'image' field
                if 'image' in service and service['image']:
                    image = service['image']
                    if self._is_valid_image(image):
                        images.add(image)
                
                # Check build context for image name
                if 'build' in service:
                    build = service['build']
                    if isinstance(build, dict) and 'image' in build:
                        image = build['image']
                        if self._is_valid_image(image):
                            images.add(image)

        return sorted(list(images))

    def migrate(self, yaml_file: str, new_registry: str, output_file: Optional[str] = None) -> str:
        """
        Migrate images in a YAML file to use new registry.
        
        Args:
            yaml_file: Path to the input YAML file
            new_registry: New registry base URL
            output_file: Optional path for output file. If not provided, will add suffix to input file
            
        Returns:
            Path to the output file
        """
        if not os.path.exists(yaml_file):
            raise FileNotFoundError(f"File not found: {yaml_file}")
            
        # Read and parse YAML
        with open(yaml_file, 'r') as f:
            try:
                compose_data = yaml.safe_load(f)
            except yaml.YAMLError as e:
                raise ValueError(f"Invalid YAML file: {e}")

        # Handle both v1 and v2+ compose file formats
        services = compose_data.get('services', compose_data)
        
        if not isinstance(services, dict):
            raise ValueError("Invalid compose file format")
            
        # Transform images
        for service in services.values():
            if isinstance(service, dict):
                if 'image' in service and service['image']:
                    service['image'] = self._transform_image(service['image'], new_registry)
                
                if 'build' in service and isinstance(service['build'], dict):
                    if 'image' in service['build']:
                        service['build']['image'] = self._transform_image(
                            service['build']['image'], 
                            new_registry
                        )

        # Determine output file path
        if not output_file:
            path = Path(yaml_file)
            output_file = str(path.parent / f"{path.stem}.migrated{path.suffix}")

        # Write transformed YAML
        with open(output_file, 'w') as f:
            yaml.dump(compose_data, f, default_flow_style=False, sort_keys=False)

        return output_file


if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Docker Compose Migration Helper')
    parser.add_argument('command', choices=['extract', 'migrate'], help='Command to execute')
    parser.add_argument('yaml_file', help='Path to docker-compose.yml or similar YAML file')
    parser.add_argument('--registry', help='New registry base URL (required for migrate)', default=None)
    parser.add_argument('--output', help='Output file path (optional for migrate)', default=None)
    
    args = parser.parse_args()
    
    helper = MigrateHelper()
    
    try:
        if args.command == 'extract':
            images = helper.extract_images(args.yaml_file)
            print('\n'.join(images))
        else:  # migrate
            if not args.registry:
                parser.error("--registry is required for migrate command")
            output = helper.migrate(args.yaml_file, args.registry, args.output)
            print(f"Migration complete. Output written to: {output}")
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
