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

    DEFAULT_TARGET_FILE = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'config', 'target-images.txt')

    def __init__(self):
        self.image_pattern = re.compile(r'^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*(?::[a-z0-9]+(?:[._-][a-z0-9]+)*)?$')
        self.target_images = set()

    def load_target_images(self, target_file: str) -> None:
        """
        Load target images from a configuration file.
        
        Args:
            target_file: Path to the target images configuration file
        """
        if not os.path.exists(target_file):
            raise FileNotFoundError(f"Target images file not found: {target_file}")
            
        self.target_images.clear()
        with open(target_file, 'r') as f:
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if not line or line.startswith('#'):
                    continue
                # Add image to target set
                if self._is_valid_image(line):
                    self.target_images.add(line)
                    # Also add version without tag for matching
                    base_image = line.split(':')[0]
                    self.target_images.add(base_image)

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

    def _should_migrate_image(self, image: str) -> bool:
        """
        Check if an image should be migrated based on target images.
        
        Args:
            image: Docker image name to check
            
        Returns:
            True if image should be migrated, False otherwise
        """
        if not self.target_images:  # If no target images loaded, migrate all
            return True
            
        # Check both full image name and base name without tag
        base_image = image.split(':')[0]
        return image in self.target_images or base_image in self.target_images

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
            
        with open(yaml_file, 'r') as f:
            try:
                compose_data = yaml.safe_load(f)
            except yaml.YAMLError as e:
                raise ValueError(f"Invalid YAML file: {e}")
                
        # Handle both v1 and v2+ compose file formats
        services = compose_data.get('services', compose_data)
        
        if not isinstance(services, dict):
            raise ValueError("Invalid compose file format")
            
        for service in services.values():
            if isinstance(service, dict):
                # Transform image in 'image' field if it should be migrated
                if 'image' in service and service['image']:
                    image = service['image']
                    if self._is_valid_image(image) and self._should_migrate_image(image):
                        service['image'] = self._transform_image(image, new_registry)
                
                # Check build context for image name
                if 'build' in service:
                    build = service['build']
                    if isinstance(build, dict) and 'image' in build:
                        image = build['image']
                        if self._is_valid_image(image) and self._should_migrate_image(image):
                            build['image'] = self._transform_image(image, new_registry)
        
        # Generate output file path if not provided
        if not output_file:
            base, ext = os.path.splitext(yaml_file)
            output_file = f"{base}.migrated{ext}"
            
        # Write transformed YAML
        with open(output_file, 'w') as f:
            yaml.dump(compose_data, f, sort_keys=False)
            
        return output_file


if __name__ == '__main__':
    import argparse
    import sys
    
    parser = argparse.ArgumentParser(description='Docker Compose Migration Helper')
    parser.add_argument('command', choices=['extract', 'migrate'], help='Command to execute')
    parser.add_argument('yaml_file', help='Path to the YAML file')
    parser.add_argument('--registry', help='New registry base URL (required for migrate)', default=None)
    parser.add_argument('--output', help='Output file path (optional for migrate)', default=None)
    parser.add_argument('--target', help='Target images configuration file (default: config/target-images.txt)', 
                       default=MigrateHelper.DEFAULT_TARGET_FILE)
    
    args = parser.parse_args()
    
    helper = MigrateHelper()
    
    # Always try to load target images file
    try:
        helper.load_target_images(args.target)
    except FileNotFoundError as e:
        print(f"Warning: {e}. Will migrate all images.", file=sys.stderr)
    
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
